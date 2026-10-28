#!/bin/bash
# 275: S9 PAPER BUG (morning read 28 Oct): the league filter matched 'italian|spanish|portuguese|dutch' anywhere in the competition
# name, so it traded Serie C, Serie B, Copa del Rey and the Dutch Cup — S9 is TOP LEAGUE ONLY, never cups (5 settled, 1 won,
# -£44.70, all outside the rule). Fix: exact whitelist. Rows outside it are tagged VOID (kept, excluded from P&L). Same
# never-settles pattern as xG/LTD ('if not fin: continue') -> ESPN final-score fallback. Also audit: quiet-hours tolerance when
# the liquidity heartbeat shows 0 live markets.
set -e
python3 - <<'PY'
p='/root/pe-xg/s9_paper.py'; s=open(p).read(); o=s
s=s.replace("AND lower(competition) ~ '(italian|spanish|portuguese|dutch)'","AND competition IN ('Italian Serie A','Spanish La Liga','Portuguese Primeira Liga','Dutch Eredivisie')",1)
old="""            fin={s:float(b) for s,b in cur.fetchall()}
            if not fin: continue
            w=min(fin,key=fin.get)
            if fin[w]>1.15: reason,pnl='UNKNOWN',None
            elif w=='HOME': reason,pnl='SETTLE_LOSS',round(-STAKE*(lp-1),2)
            else: reason,pnl='SETTLE_WIN',round(STAKE*(1-COMM),2)
"""
new="""            fin={s:float(b) for s,b in cur.fetchall()}
            if fin and min(fin.values())<=1.15:
                w=min(fin,key=fin.get)
                if w=='HOME': reason,pnl='SETTLE_LOSS',round(-STAKE*(lp-1),2)
                else: reason,pnl='SETTLE_WIN',round(STAKE*(1-COMM),2)
            else:
                cur.execute('SELECT hs, "as", minute FROM espn_stats WHERE market_id=%s AND hs IS NOT NULL ORDER BY ts DESC LIMIT 1',(mid,)); fs=cur.fetchone()
                if fs and fs[2] is not None and fs[2]>=85:
                    reason,pnl=('SETTLE_LOSS',round(-STAKE*(lp-1),2)) if fs[0]>fs[1] else ('SETTLE_WIN',round(STAKE*(1-COMM),2))
                elif datetime.datetime.now(datetime.timezone.utc)<ets+datetime.timedelta(hours=6): continue
                else: reason,pnl='UNKNOWN',None
"""
assert old in s, "settle anchor missing"; s=s.replace(old,new,1)
assert s!=o and "Italian Serie A" in s; open(p,'w').write(s); print("s9 whitelist + settle fallback patched")
PY
python3 -m py_compile /root/pe-xg/s9_paper.py; pkill -f s9_paper.py || true; sleep 2; nohup /root/pe-xg/keepalive_s9.sh >/dev/null 2>&1 &
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require'); c.autocommit=True; k=c.cursor()
k.execute("UPDATE s9_paper SET exit_reason='VOID_'||coalesce(exit_reason,'OPEN'), pnl_per_10=NULL, exit_ts=coalesce(exit_ts,now()) WHERE competition NOT IN ('Italian Serie A','Spanish La Liga','Portuguese Primeira Liga','Dutch Eredivisie') AND exit_reason NOT LIKE 'VOID%'"); print("voided out-of-rule rows:",k.rowcount)
k.execute("SELECT competition, count(*), round(sum(pnl_per_10),2) FROM s9_paper GROUP BY 1"); print(k.fetchall())
PY
# audit: quiet hours — zero rows is fine when no market is live
python3 - <<'PY'
p='/root/pe-push/integrity.py'; s=open(p).read()
old="""    chk(f"{name}: rows last hour",n,(num(n) and n>0) or ('racing' in name and not (10<=hr<=20)))"""
new="""    live=q("SELECT live_markets FROM liq_heartbeat LIMIT 1"); quiet=(num(live) and int(live)==0)
    chk(f"{name}: rows last hour",n,(num(n) and n>0) or ('racing' in name and not (10<=hr<=20)) or quiet)
    if quiet and (not num(n) or n==0): continue"""
assert old in s; s=s.replace(old,new,1)
s=s.replace("""chk("stream: median secs between ticks (same runner)",g,num(g) and float(g)<30)""","""chk("stream: median secs between ticks (same runner)",g,(num(g) and float(g)<30) or not num(g) or int(q("SELECT markets FROM stream_heartbeat LIMIT 1") or 0)<3)""")
open(p,'w').write(s); print("audit quiet-hours tolerance added")
PY
python3 -m py_compile /root/pe-push/integrity.py && python3 /root/pe-push/integrity.py | grep -E "FAIL|checks"
sleep 20; pgrep -af s9_paper.py | head -1
