#!/bin/bash
# 213: LATE LAY-OVER PAPER BOT. The one theme every honest slice agrees on: Over 2.5 is too short late in a game with <= 1 goal.
#   True-goal history (3,440 top-league games): lay at 70'/75', band 2.5-5: +1.5/+3.9 (exit +10), +2.4/+5.3 (next goal), t 4-7.
#   Live ladders 20-25 Oct (1,168 trades, all leagues): 70' +1.15 (n 179), 75' +6.02 (n 144, 85% win); 55'-65' negative live -> excluded.
# Rule: 70'-77', <= 1 goal, lay Over 2.5 at 1.6-5.0 with >= £10 available, £10 paper. Exit: 2 min after the next goal (Over back falls
# 30%+ sane-to-sane) at the Over back price, else at the first sane sample from 90', else settle (Over back <= 1.15 at the end = lost).
# Goal count: ESPN score where the event is matched, otherwise draw-book jumps on the event's Match Odds market. Table late_over_paper.
# Gate to £2 live: 60 settled, positive, 70' and 75' both not negative.
set -e
mkdir -p /root/pe-xg && cat > /root/pe-xg/late_over_paper.py <<'PYFILE'
import sys, time, datetime, psycopg2
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
COMM=0.02; STAKE=10.0; JUMP=1.25
def connect():
    c=psycopg2.connect(DB,sslmode='require'); c.autocommit=True; return c
con=connect(); cur=con.cursor()
cur.execute("""CREATE TABLE IF NOT EXISTS late_over_paper (id SERIAL PRIMARY KEY, ou_market_id TEXT, mo_market_id TEXT, event_name TEXT, competition TEXT, entry_ts TIMESTAMPTZ, minute INT,
  lay_px NUMERIC, lay_sz NUMERIC, goals INT, goal_src TEXT, goal_ts TIMESTAMPTZ, exit_ts TIMESTAMPTZ, exit_px NUMERIC, exit_reason TEXT, pnl_per_10 NUMERIC, UNIQUE (ou_market_id));
CREATE TABLE IF NOT EXISTS late_over_heartbeat (id INT PRIMARY KEY, last_seen TIMESTAMPTZ, candidates INT, open_trades INT)""")
SANE="back_px IS NOT NULL AND lay_px IS NOT NULL AND lay_px<=back_px*1.2"
def pnl_hedge(lay,back):
    p=STAKE*(1-lay/back); return round(p*(1-COMM) if p>0 else p,2)
def mo_market(ev):
    cur.execute("SELECT market_id FROM liq_sample WHERE event_name=%s AND mkt='MO' AND ts>now()-interval '4 hours' ORDER BY ts DESC LIMIT 1",(ev,)); r=cur.fetchone(); return r[0] if r else None
def goals_now(ev,mo):
    if mo:
        cur.execute('SELECT hs, "as" FROM espn_stats WHERE market_id=%s AND hs IS NOT NULL AND ts>now()-interval \'4 minutes\' ORDER BY ts DESC LIMIT 1',(mo,)); r=cur.fetchone()
        if r: return r[0]+r[1],'espn'
        cur.execute(f"""WITH d AS (SELECT back_px, lag(back_px) OVER (ORDER BY ts) pb, lag(lay_px) OVER (ORDER BY ts) pl FROM liq_sample WHERE market_id=%s AND mkt='MO' AND sel='DRAW' AND {SANE})
                        SELECT count(*) FROM d WHERE pb IS NOT NULL AND back_px>=pb*%s AND back_px>=pl*%s""",(mo,JUMP,JUMP)); return cur.fetchone()[0],'jumps'
    return None,None
def over_drop_after(mid,ts):
    cur.execute(f"""WITH d AS (SELECT ts, back_px, lag(back_px) OVER (ORDER BY ts) pb FROM liq_sample WHERE market_id=%s AND mkt='OU25' AND sel='OVER' AND {SANE})
                    SELECT ts FROM d WHERE pb IS NOT NULL AND back_px<=pb*0.7 AND ts>%s ORDER BY ts LIMIT 1""",(mid,ts)); r=cur.fetchone(); return r[0] if r else None
def back_from(mid,ts=None,minute=None):
    if ts is not None: cur.execute(f"SELECT back_px, ts FROM liq_sample WHERE market_id=%s AND mkt='OU25' AND sel='OVER' AND ts>=%s AND {SANE} ORDER BY ts LIMIT 1",(mid,ts))
    else: cur.execute(f"SELECT back_px, ts FROM liq_sample WHERE market_id=%s AND mkt='OU25' AND sel='OVER' AND minute>=%s AND {SANE} ORDER BY ts LIMIT 1",(mid,minute))
    return cur.fetchone()
last_hb=0
while True:
    try:
        cur.execute(f"""SELECT DISTINCT ON (market_id) market_id, event_name, competition, ts, minute, lay_px, lay_sz, total_matched FROM liq_sample
                        WHERE mkt='OU25' AND sel='OVER' AND ts>now()-interval '3 minutes' AND minute BETWEEN 70 AND 77 AND {SANE} AND lay_px BETWEEN 1.6 AND 5.0 AND coalesce(lay_sz,0)>=10
                        ORDER BY market_id, ts DESC""")
        cands=cur.fetchall()
        for mid,ev,comp,ts,mn,lp,lsz,tm in cands:
            cur.execute("SELECT 1 FROM late_over_paper WHERE ou_market_id=%s",(mid,))
            if cur.fetchone(): continue
            mo=mo_market(ev); g,src=goals_now(ev,mo)
            if g is None or g>1: continue
            cur.execute("INSERT INTO late_over_paper (ou_market_id,mo_market_id,event_name,competition,entry_ts,minute,lay_px,lay_sz,goals,goal_src) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) ON CONFLICT DO NOTHING",(mid,mo,ev,comp,ts,mn,lp,lsz,g,src))
            if cur.rowcount: print(f"LAY OVER2.5 {ev} [{comp}] {mn}' goals {g} ({src}) @ {lp} (£{lsz})",flush=True)
        # exits
        cur.execute("SELECT id, ou_market_id, lay_px, entry_ts FROM late_over_paper WHERE exit_ts IS NULL")
        for pid,mid,lp,ets in cur.fetchall():
            lp=float(lp); gts=over_drop_after(mid,ets)
            if gts is not None:
                r=back_from(mid,ts=gts+datetime.timedelta(seconds=120))
                if r:
                    pnl=pnl_hedge(lp,float(r[0])); cur.execute("UPDATE late_over_paper SET goal_ts=%s, exit_ts=%s, exit_px=%s, exit_reason='GOAL', pnl_per_10=%s WHERE id=%s",(gts,r[1],r[0],pnl,pid)); print(f"EXIT GOAL {mid} {lp}->{r[0]} {pnl:+.2f}",flush=True)
                continue
            r=back_from(mid,minute=90)
            if r:
                pnl=pnl_hedge(lp,float(r[0])); cur.execute("UPDATE late_over_paper SET exit_ts=%s, exit_px=%s, exit_reason='M90', pnl_per_10=%s WHERE id=%s",(r[1],r[0],pnl,pid)); print(f"EXIT 90' {mid} {lp}->{r[0]} {pnl:+.2f}",flush=True); continue
            cur.execute("SELECT 1 FROM liq_sample WHERE market_id=%s AND ts>now()-interval '20 minutes' LIMIT 1",(mid,))
            if cur.fetchone(): continue
            cur.execute(f"SELECT back_px FROM liq_sample WHERE market_id=%s AND mkt='OU25' AND sel='OVER' AND {SANE} AND minute>=85 ORDER BY ts DESC LIMIT 1",(mid,)); r=cur.fetchone()
            if not r: reason,pnl='UNKNOWN',None
            elif float(r[0])<=1.15: reason,pnl='SETTLE_LOSS',round(-STAKE*(lp-1),2)
            elif float(r[0])>=5: reason,pnl='SETTLE_WIN',round(STAKE*(1-COMM),2)
            else: reason,pnl='UNKNOWN',None
            cur.execute("UPDATE late_over_paper SET exit_ts=now(), exit_px=%s, exit_reason=%s, pnl_per_10=%s WHERE id=%s",(r[0] if r else None,reason,pnl,pid))
        if time.time()-last_hb>60:
            cur.execute("INSERT INTO late_over_heartbeat VALUES (1,now(),%s,(SELECT count(*) FROM late_over_paper WHERE exit_ts IS NULL)) ON CONFLICT (id) DO UPDATE SET last_seen=now(), candidates=EXCLUDED.candidates, open_trades=EXCLUDED.open_trades",(len(cands),)); last_hb=time.time()
        time.sleep(30)
    except Exception as e:
        print("loop",repr(e)[:200],flush=True); time.sleep(20)
        try: con=connect(); cur=con.cursor()
        except Exception: pass
PYFILE
python3 -m py_compile /root/pe-xg/late_over_paper.py
cat > /root/pe-xg/keepalive_lo.sh <<'SH'
#!/bin/bash
pgrep -f late_over_paper.py >/dev/null || (cd /root/pe-xg && nohup python3 late_over_paper.py >> late_over.log 2>&1 &)
SH
chmod +x /root/pe-xg/keepalive_lo.sh
( crontab -l 2>/dev/null | grep -v keepalive_lo ; echo "* * * * * /root/pe-xg/keepalive_lo.sh" ) | crontab -
/root/pe-xg/keepalive_lo.sh; sleep 75; pgrep -af late_over_paper.py | head -1; tail -5 /root/pe-xg/late_over.log
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require').cursor()
c.execute("SELECT * FROM late_over_heartbeat"); print("heartbeat (candidates, open):",c.fetchall())
c.execute("SELECT event_name, competition, minute, lay_px, goals, goal_src FROM late_over_paper ORDER BY entry_ts DESC LIMIT 8"); [print("  ",r) for r in c.fetchall()]
PY
