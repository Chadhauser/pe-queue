#!/bin/bash
# 194: IN-PLAY LAY-THE-DRAW PAPER BOT. Rule (sweep survivor + 192 live replay +£1.46/£10 over 185 trades): a Match Odds market that is
# 0-0 (no goal reopen recorded, both sides >= 1.30) at 46', 60' or 75', draw LAY price 1.5-2.5 with >= £20 available and >= £5k
# matched -> paper lay £10 at the lay price. Exit: first ladder sample >= 120 s after the next goal reopen, at the draw BACK price; or
# settlement at the close (draw won -> lose liability; else +£9.80). One paper trade per market per trigger. Reads the liquidity
# recorder's tables every 20 s — no extra Betfair calls. Daily 05:45 settle pass closes anything left. Table: ltd_inplay_paper.
# Gate to £2 live: 50 settled paper trades, positive total, each trigger not negative.
mkdir -p /root/pe-ltd && cat > /root/pe-ltd/ltd_paper.py <<'PYFILE'
import sys, time, datetime, psycopg2
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
COMM=0.02; STAKE=10.0; TRIGS=((46,48),(60,62),(75,77))
def connect():
    c=psycopg2.connect(DB,sslmode='require'); c.autocommit=True; return c
con=connect(); cur=con.cursor()
cur.execute("""CREATE TABLE IF NOT EXISTS ltd_inplay_paper (id SERIAL PRIMARY KEY, market_id TEXT, event_name TEXT, competition TEXT, trig INT, entry_ts TIMESTAMPTZ, entry_minute INT,
  lay_px NUMERIC, lay_sz NUMERIC, total_matched NUMERIC, home_ltp NUMERIC, away_ltp NUMERIC, exit_ts TIMESTAMPTZ, exit_px NUMERIC, exit_reason TEXT, pnl_per_10 NUMERIC, UNIQUE (market_id, trig));
CREATE TABLE IF NOT EXISTS ltd_heartbeat (id INT PRIMARY KEY, last_seen TIMESTAMPTZ, open_trades INT, today INT)""")
def pnl_hedge(lay,back):
    p=STAKE*(1-lay/back); return round(p*(1-COMM) if p>0 else p,2)
last_hb=0
while True:
    try:
        # ---- entries: latest MO draw sample per in-play market inside a trigger window
        cur.execute("""WITH last AS (
             SELECT DISTINCT ON (market_id) market_id, event_name, competition, ts, minute, lay_px, lay_sz, total_matched
             FROM liq_sample WHERE mkt='MO' AND sel='DRAW' AND ts>now()-interval '90 seconds' ORDER BY market_id, ts DESC)
           SELECT l.*, (SELECT ltp FROM liq_sample h WHERE h.market_id=l.market_id AND h.mkt='MO' AND h.sel='HOME' AND h.ts<=l.ts ORDER BY h.ts DESC LIMIT 1) hl,
                       (SELECT ltp FROM liq_sample a WHERE a.market_id=l.market_id AND a.mkt='MO' AND a.sel='AWAY' AND a.ts<=l.ts ORDER BY a.ts DESC LIMIT 1) al
           FROM last l WHERE l.lay_px BETWEEN 1.5 AND 2.5 AND coalesce(l.lay_sz,0)>=20 AND coalesce(l.total_matched,0)>=5000""")
        for mid,ev,comp,ts,minute,lp,lsz,tm,hl,al in cur.fetchall():
            trig=next((t for t,(a,b) in zip((46,60,75),TRIGS) if a<=(minute or -1)<=b),None)
            if trig is None or hl is None or al is None or min(float(hl),float(al))<1.30: continue
            cur.execute("SELECT 1 FROM liq_goal_depth WHERE market_id=%s AND mkt='MO' AND goal_ts<%s LIMIT 1",(mid,ts))
            if cur.fetchone(): continue                                  # not 0-0
            cur.execute("""INSERT INTO ltd_inplay_paper (market_id,event_name,competition,trig,entry_ts,entry_minute,lay_px,lay_sz,total_matched,home_ltp,away_ltp)
                           VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) ON CONFLICT DO NOTHING""",(mid,ev,comp,trig,ts,minute,lp,lsz,tm,hl,al))
            if cur.rowcount: print(f"PAPER LAY DRAW {ev} [{comp}] {minute}' @ {lp} (£{lsz} avail)",flush=True)
        # ---- exits on goals
        cur.execute("""SELECT p.id, p.market_id, p.lay_px, g.goal_ts FROM ltd_inplay_paper p
                       JOIN LATERAL (SELECT min(goal_ts) goal_ts FROM liq_goal_depth d WHERE d.market_id=p.market_id AND d.mkt='MO' AND d.goal_ts>p.entry_ts) g ON true
                       WHERE p.exit_ts IS NULL AND g.goal_ts IS NOT NULL AND g.goal_ts < now()-interval '120 seconds'""")
        for pid,mid,lp,gts in cur.fetchall():
            cur.execute("SELECT back_px, ts FROM liq_sample WHERE market_id=%s AND mkt='MO' AND sel='DRAW' AND ts>=%s+interval '120 seconds' AND back_px IS NOT NULL ORDER BY ts LIMIT 1",(mid,gts))
            r=cur.fetchone()
            if not r: continue
            bp,xts=r; pnl=pnl_hedge(float(lp),float(bp))
            cur.execute("UPDATE ltd_inplay_paper SET exit_ts=%s, exit_px=%s, exit_reason='GOAL', pnl_per_10=%s WHERE id=%s",(xts,bp,pnl,pid)); print(f"EXIT GOAL {mid} lay {lp} -> back {bp} = {pnl:+.2f}",flush=True)
        # ---- settle closed markets (no sample for 20 min): result from the final prices
        cur.execute("""SELECT p.id, p.market_id, p.lay_px FROM ltd_inplay_paper p WHERE p.exit_ts IS NULL AND p.entry_ts < now()-interval '40 minutes'
                       AND NOT EXISTS (SELECT 1 FROM liq_sample s WHERE s.market_id=p.market_id AND s.ts>now()-interval '20 minutes')""")
        for pid,mid,lp in cur.fetchall():
            cur.execute("SELECT sel, ltp FROM liq_sample WHERE market_id=%s AND mkt='MO' AND ltp IS NOT NULL AND ts=(SELECT max(ts) FROM liq_sample WHERE market_id=%s AND mkt='MO' AND ltp IS NOT NULL)",(mid,mid))
            fin={s:float(v) for s,v in cur.fetchall()}
            if not fin: continue
            w=min(fin,key=fin.get)
            if fin[w]>1.15: reason,pnl='UNKNOWN',None
            elif w=='DRAW': reason,pnl='SETTLE_LOSS',round(-STAKE*(float(lp)-1),2)
            else: reason,pnl='SETTLE_WIN',round(STAKE*(1-COMM),2)
            cur.execute("UPDATE ltd_inplay_paper SET exit_ts=now(), exit_px=%s, exit_reason=%s, pnl_per_10=%s WHERE id=%s",(fin.get('DRAW'),reason,pnl,pid))
        if time.time()-last_hb>60:
            cur.execute("INSERT INTO ltd_heartbeat VALUES (1,now(),(SELECT count(*) FROM ltd_inplay_paper WHERE exit_ts IS NULL),(SELECT count(*) FROM ltd_inplay_paper WHERE entry_ts::date=current_date)) ON CONFLICT (id) DO UPDATE SET last_seen=now(), open_trades=EXCLUDED.open_trades, today=EXCLUDED.today"); last_hb=time.time()
        time.sleep(20)
    except Exception as e:
        print("loop",repr(e)[:200],flush=True); time.sleep(20)
        try: con=connect(); cur=con.cursor()
        except Exception: pass
PYFILE
python3 -m py_compile /root/pe-ltd/ltd_paper.py || exit 1
cat > /root/pe-ltd/keepalive.sh <<'SH'
#!/bin/bash
pgrep -f ltd_paper.py >/dev/null || (cd /root/pe-ltd && nohup python3 ltd_paper.py >> ltd.log 2>&1 &)
SH
chmod +x /root/pe-ltd/keepalive.sh
( crontab -l 2>/dev/null | grep -v pe-ltd ; echo "* * * * * /root/pe-ltd/keepalive.sh" ) | crontab -
/root/pe-ltd/keepalive.sh; sleep 45; pgrep -af ltd_paper.py | head -1; tail -5 /root/pe-ltd/ltd.log
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require').cursor(); c.execute("SELECT * FROM ltd_heartbeat"); print("ltd heartbeat:",c.fetchall())
c.execute("SELECT count(*) FROM liq_sample WHERE mkt='MO' AND sel='DRAW' AND ts>now()-interval '90 seconds'"); print("draw samples in the last 90s (feed the bot reads):",c.fetchone()[0])
PY
