#!/bin/bash
# 247: (A) S9 PAPER LINE. Peter's original Serie A rule re-tested on our data (true results, KO = first in-play price): lay the home side
# at 4.0-4.5 in IT +£4.98/£10 (n 43, 88% win), PT +£6.23 (n 23), NL +£4.72 (n 25), ES +£2.54 (n 41); GB flat, FR/DE negative. Small
# samples but consistent with the 14-season vendor claim (89% WR). Paper bot: Italian/Spanish/Portuguese/Dutch league games, home LAY
# price 4.0-4.5 at the first in-play sample (minute <= 3), £10 paper lay; exit at the first home goal (home best back falls 30%+
# sane-to-sane) hedged 120 s later — Peter's S9 stop rule — else settle at FT from the final book. Table s9_paper. Gate: 40 settled.
# (B) RETENTION: nightly 03:30 — xx_tape 14 days, ip_tape 30 days, stream_ticks 30 days, bf_price_log 60 days. DB is 31 GB.
set -e
mkdir -p /root/pe-xg && cat > /root/pe-xg/s9_paper.py <<'PYFILE'
import sys, time, datetime, psycopg2
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
COMM=0.02; STAKE=10.0; LEAGUES=('italian','spanish','portuguese','dutch')
def connect():
    c=psycopg2.connect(DB,sslmode='require'); c.autocommit=True; return c
con=connect(); cur=con.cursor()
cur.execute("""CREATE TABLE IF NOT EXISTS s9_paper (id SERIAL PRIMARY KEY, market_id TEXT UNIQUE, event_name TEXT, competition TEXT, entry_ts TIMESTAMPTZ, minute INT, lay_px NUMERIC, lay_sz NUMERIC,
  goal_ts TIMESTAMPTZ, exit_ts TIMESTAMPTZ, exit_px NUMERIC, exit_reason TEXT, pnl_per_10 NUMERIC);
CREATE TABLE IF NOT EXISTS s9_heartbeat (id INT PRIMARY KEY, last_seen TIMESTAMPTZ, open_trades INT, today INT)""")
SANE="back_px IS NOT NULL AND lay_px IS NOT NULL AND lay_px<=back_px*1.2"
def pnl_hedge(lay,back):
    p=STAKE*(1-lay/back); return round(p*(1-COMM) if p>0 else p,2)
last_hb=0
while True:
    try:
        cur.execute(f"""SELECT DISTINCT ON (market_id) market_id, event_name, competition, ts, minute, lay_px, lay_sz FROM liq_sample
                        WHERE mkt='MO' AND sel='HOME' AND ts>now()-interval '4 minutes' AND minute BETWEEN 0 AND 3 AND {SANE} AND lay_px BETWEEN 4.0 AND 4.5 AND coalesce(lay_sz,0)>=10
                        AND lower(competition) ~ '(italian|spanish|portuguese|dutch)' ORDER BY market_id, ts""")
        for mid,ev,comp,ts,mn,lp,lsz in cur.fetchall():
            cur.execute("INSERT INTO s9_paper (market_id,event_name,competition,entry_ts,minute,lay_px,lay_sz) VALUES (%s,%s,%s,%s,%s,%s,%s) ON CONFLICT DO NOTHING",(mid,ev,comp,ts,mn,lp,lsz))
            if cur.rowcount: print(f"S9 LAY HOME {ev} [{comp}] {mn}' @ {lp}",flush=True)
        cur.execute("SELECT id, market_id, lay_px, entry_ts FROM s9_paper WHERE exit_ts IS NULL")
        for pid,mid,lp,ets in cur.fetchall():
            lp=float(lp)
            cur.execute(f"""WITH d AS (SELECT ts, back_px, lag(back_px) OVER (ORDER BY ts) pb FROM liq_sample WHERE market_id=%s AND mkt='MO' AND sel='HOME' AND {SANE})
                            SELECT ts FROM d WHERE pb IS NOT NULL AND back_px<=pb*0.7 AND ts>%s ORDER BY ts LIMIT 1""",(mid,ets)); g=cur.fetchone()
            if g:
                cur.execute(f"SELECT back_px, ts FROM liq_sample WHERE market_id=%s AND mkt='MO' AND sel='HOME' AND ts>=%s AND {SANE} ORDER BY ts LIMIT 1",(mid,g[0]+datetime.timedelta(seconds=120))); r=cur.fetchone()
                if r:
                    pnl=pnl_hedge(lp,float(r[0])); cur.execute("UPDATE s9_paper SET goal_ts=%s, exit_ts=%s, exit_px=%s, exit_reason='HOME_GOAL', pnl_per_10=%s WHERE id=%s",(g[0],r[1],r[0],pnl,pid)); print(f"S9 EXIT home goal {mid} {lp}->{r[0]} {pnl:+.2f}",flush=True)
                continue
            cur.execute("SELECT 1 FROM liq_sample WHERE market_id=%s AND ts>now()-interval '20 minutes' LIMIT 1",(mid,))
            if cur.fetchone() or datetime.datetime.now(datetime.timezone.utc)<ets+datetime.timedelta(minutes=100): continue
            cur.execute(f"""SELECT sel, back_px FROM liq_sample WHERE market_id=%s AND mkt='MO' AND back_px IS NOT NULL AND ts=(SELECT max(ts) FROM liq_sample WHERE market_id=%s AND mkt='MO' AND sel='DRAW' AND {SANE} AND minute>=85)""",(mid,mid))
            fin={s:float(b) for s,b in cur.fetchall()}
            if not fin: continue
            w=min(fin,key=fin.get)
            if fin[w]>1.15: reason,pnl='UNKNOWN',None
            elif w=='HOME': reason,pnl='SETTLE_LOSS',round(-STAKE*(lp-1),2)
            else: reason,pnl='SETTLE_WIN',round(STAKE*(1-COMM),2)
            cur.execute("UPDATE s9_paper SET exit_ts=now(), exit_reason=%s, pnl_per_10=%s WHERE id=%s",(reason,pnl,pid))
        if time.time()-last_hb>60:
            cur.execute("INSERT INTO s9_heartbeat VALUES (1,now(),(SELECT count(*) FROM s9_paper WHERE exit_ts IS NULL),(SELECT count(*) FROM s9_paper WHERE entry_ts::date=current_date)) ON CONFLICT (id) DO UPDATE SET last_seen=now(), open_trades=EXCLUDED.open_trades, today=EXCLUDED.today"); last_hb=time.time()
        time.sleep(45)
    except Exception as e:
        print("loop",repr(e)[:200],flush=True); time.sleep(20)
        try: con=connect(); cur=con.cursor()
        except Exception: pass
PYFILE
python3 -m py_compile /root/pe-xg/s9_paper.py
cat > /root/pe-xg/keepalive_s9.sh <<'SH'
#!/bin/bash
pgrep -f s9_paper.py >/dev/null || (cd /root/pe-xg && nohup python3 s9_paper.py >> s9.log 2>&1 &)
SH
chmod +x /root/pe-xg/keepalive_s9.sh
( crontab -l 2>/dev/null | grep -v keepalive_s9 ; echo "* * * * * /root/pe-xg/keepalive_s9.sh" ) | crontab -
/root/pe-xg/keepalive_s9.sh; sleep 40; pgrep -af s9_paper.py | head -1
cat > /root/pe-factory/retention.sh <<'SH'
#!/bin/bash
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require'); c.autocommit=True; k=c.cursor(); k.execute("SET statement_timeout='1800s'")
for t,col,days in (('xx_tape','ts',14),('ip_tape','ts',30),('stream_ticks','ts_recv',30),('bf_price_log','ts',60)):
    try: k.execute(f"DELETE FROM {t} WHERE {col} < now() - interval '{days} days'"); print(t,"deleted",k.rowcount)
    except Exception as e: print(t,"skip",str(e)[:80])
PY
SH
chmod +x /root/pe-factory/retention.sh
( crontab -l 2>/dev/null | grep -v "pe-factory/retention.sh" ; echo "30 3 * * * /root/pe-factory/retention.sh >> /root/pe-factory/retention.log 2>&1" ) | crontab -
echo "retention nightly 03:30 installed"
