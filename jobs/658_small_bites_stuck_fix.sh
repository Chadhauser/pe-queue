#!/bin/bash
# 658 (Wed 18 Nov 2026, 07:00). PAPER ONLY. Small bites forward: the 1,569 trades that exited normally made +£149.17 (+£4.75 per £100,
# in line with the backtest); the -£200 total comes from 175 "stuck" trades booked at the worst case -£2 each (-£350), mostly markets the
# stream stopped sending (its subscription is capped at 200 markets) rather than real losses. Fix, honestly:
#  1. A stuck trade now exits at the real price from the new full recorder (book_snap: best lay for a back) at the first minute at or after
#     the exit time; if the recorder has nothing, it is settled on Betfair's result as a bet held to the end (never the flattering way).
#  2. Re-settle the 175 existing stuck trades the same way.
# Report: reports/small_bites_658.md
T=/root/pe-sports/team; F=$T/small_bites_live.py; R=/root/pe-queue/reports/small_bites_658.md
cat > $T/sb_resettle.py <<'PY'
import sys, requests, datetime as dt; sys.path.insert(0,'/root/pe-queue/runner'); import creds, psycopg2
COMM=0.02; ST=2.0
def net(g): return g*(1-COMM) if g>0 else g
APP,USER,PW=creds.betfair()
def login():
    r0=requests.post("https://identitysso.betfair.com/api/login",data={"username":USER,"password":PW},headers={"X-Application":APP,"Accept":"application/json"},timeout=20)
    return r0.json()['token']
con=psycopg2.connect(creds.pg_local(),sslmode='disable'); con.autocommit=True; c=con.cursor()
c.execute("SELECT id, market_id, sel_id, side, h, entry_min, entry_px FROM small_bites_paper WHERE status='stuck'"); S=c.fetchall()
by_book=0; by_result=0; left=0; tok=None
for i, mid, sid, side, H, em, epx in S:
    due=em+dt.timedelta(minutes=H); epx=float(epx)
    c.execute("SELECT ts, back1, lay1 FROM book_snap WHERE market_id=%s AND sel_id=%s AND ts>=%s AND status='OPEN' AND back1 IS NOT NULL AND lay1 IS NOT NULL ORDER BY ts LIMIT 1",(mid,int(sid),due))
    r=c.fetchone()
    if r:
        g = ST*(epx/float(r[2])-1) if side=='back' else ST*(1-epx/float(r[1]))
        c.execute("UPDATE small_bites_paper SET status='closed', exit_min=%s, exit_px=%s, pnl=%s WHERE id=%s",(r[0], r[2] if side=='back' else r[1], round(net(g),4), i)); by_book+=1; continue
    try:
        tok=tok or login()
        b=requests.post("https://api.betfair.com/exchange/betting/rest/v1.0/listMarketBook/",json={"marketIds":[mid]},headers={"X-Application":APP,"X-Authentication":tok,"Content-Type":"application/json"},timeout=20).json()
        rn=[x for x in (b[0].get('runners',[]) if b else []) if str(x['selectionId'])==str(sid)]
        if b and b[0].get('status')=='CLOSED' and rn and rn[0].get('status') in ('WINNER','LOSER'):
            won=rn[0]['status']=='WINNER'
            g=((epx-1)*ST if won else -ST) if side=='back' else (-(epx-1)*ST if won else ST)
            c.execute("UPDATE small_bites_paper SET status='settled_result', pnl=%s WHERE id=%s",(round(net(g),4),i)); by_result+=1; continue
    except Exception as e: print("result lookup",mid,repr(e)[:80])
    left+=1
print(f"stuck {len(S)}: exited at the recorder's real price {by_book}, settled on the Betfair result {by_result}, still unresolved (kept at -£2) {left}")
c.execute("SELECT status, count(*), round(sum(pnl),2) FROM small_bites_paper GROUP BY 1 ORDER BY 1"); print("now:", c.fetchall())
c.execute("SELECT count(*), round(sum(pnl),2), round(sum(pnl)/(count(*)*2)*100,2) FROM small_bites_paper WHERE pnl IS NOT NULL"); print("total trades, £, per £100:", c.fetchone())
c.execute("SELECT cell, count(*), round(sum(pnl),2) FROM small_bites_paper WHERE pnl IS NOT NULL GROUP BY 1 ORDER BY 3 DESC"); [print("  ",r) for r in c.fetchall()]
PY
{ echo "# 658 — $(date -u '+%F %H:%M') UTC"; echo '```'
cp $F $F.bak_658
python3 - "$F" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read()
old="""                elif m >= due + dt.timedelta(minutes=60):
                    c.execute("UPDATE small_bites_paper SET status='stuck', pnl=%s WHERE id=%s", (-ST if side == 'back' else None, i))"""
new="""                else:
                    c.execute("SELECT ts, back1, lay1 FROM book_snap WHERE market_id=%s AND sel_id=%s AND ts>=%s AND status='OPEN' AND back1 IS NOT NULL AND lay1 IS NOT NULL ORDER BY ts LIMIT 1", (mid, int(sid), due))
                    bk = c.fetchone()   # 658: the full recorder covers markets the stream dropped
                    if bk:
                        x_px = float(bk[2]) if side == 'back' else float(bk[1]); g = g_back_lay(float(epx), x_px) if side == 'back' else g_lay_back(float(epx), x_px)
                        c.execute("UPDATE small_bites_paper SET exit_min=%s, exit_px=%s, status='closed', pnl=%s WHERE id=%s", (bk[0], x_px, round(net(g), 4), i))
                    elif m >= due + dt.timedelta(minutes=60):
                        c.execute("UPDATE small_bites_paper SET status='stuck', pnl=%s WHERE id=%s", (-ST if side == 'back' else None, i))"""
print("patched" if s.count(old)==1 else f"anchor count {s.count(old)}"); s=s.replace(old,new); open(p,'w').write(s)
PY
python3 -m py_compile $F && echo compiles || { cp $F.bak_658 $F; echo "restored"; }
pkill -f small_bites_live.py; sleep 30; echo "bot processes: $(pgrep -f small_bites_live.py | wc -l)"
timeout 900 python3 $T/sb_resettle.py
echo '```'; } > $R 2>&1
cd /root/pe-queue && git add $R && git commit -qm "658: small bites stuck fix" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
