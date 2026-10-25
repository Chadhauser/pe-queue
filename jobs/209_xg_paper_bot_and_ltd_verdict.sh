#!/bin/bash
# 209: VERDICT + REDEPLOY. Price-only lay-the-draw in a level game is dead on two independent honest tests (206/208: true Understat goal
# minutes, 60' -1.72 and 75' -2.29 per £10, t -4/-5, both halves; 207: live ladders with book-based goals, 148 trades, -0.13). The
# real-order LTD bot is disabled (ltd_control.enabled=false; code stays). The paper bot keeps collecting on the lower leagues the
# history does not cover (free; verdict at 100 settled). The two xG-conditioned rules that passed the same honest test go to paper now:
#   XG_DOM : 55'-78', level score, one side ahead on cumulative xG by >= 0.5 -> lay the OTHER side at 5.0-30 (MO), exit 2 min after the
#            next goal at its back price, else settle at FT.   (history: +2.38/£10 n 1,109 t 5.0; 65'-75' +2.6/+3.8/+3.6)
#   XG_OPEN: 55'-78', <= 1 goal, total xG >= 1.0 -> lay Over 2.5 at 2.5-5.0, exit 20 min later at the Over back price, or 2 min after a
#            goal if one comes first; settle from the final score if the market is gone.  (history: +1.16/£10 n 2,658 t 8.4; 60'-70' +1.2/+2.0/+2.4)
# Score and clock from the ESPN tape (espn_stats, matched market), xG from ip_stats (API-Football, xG-only polling from 202). No xG row
# within 4 min -> no entry. Tables xg_paper, xg_heartbeat. Keepalive on cron.
set -e
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require'); c.autocommit=True; k=c.cursor()
k.execute("UPDATE ltd_control SET enabled=false, note='disabled 25 Oct 14:35: price-only LTD dead on true-goal history (206/208) and live ladders (207)' WHERE id=1"); print("ltd_control disabled:",k.rowcount)
PY
mkdir -p /root/pe-xg && cat > /root/pe-xg/xg_paper.py <<'PYFILE'
import sys, time, datetime, psycopg2
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
COMM=0.02; STAKE=10.0; JUMP=1.25
def connect():
    c=psycopg2.connect(DB,sslmode='require'); c.autocommit=True; return c
con=connect(); cur=con.cursor()
cur.execute("""CREATE TABLE IF NOT EXISTS xg_paper (id SERIAL PRIMARY KEY, rule TEXT, market_id TEXT, event_name TEXT, competition TEXT, entry_ts TIMESTAMPTZ, minute INT, mkt TEXT, sel TEXT,
  lay_px NUMERIC, lay_sz NUMERIC, hs INT, "as" INT, h_xg NUMERIC, a_xg NUMERIC, goal_ts TIMESTAMPTZ, exit_ts TIMESTAMPTZ, exit_px NUMERIC, exit_reason TEXT, pnl_per_10 NUMERIC, UNIQUE (market_id, rule));
CREATE TABLE IF NOT EXISTS xg_heartbeat (id INT PRIMARY KEY, last_seen TIMESTAMPTZ, candidates INT, with_xg INT, open_trades INT)""")
SANE="back_px IS NOT NULL AND lay_px IS NOT NULL AND lay_px<=back_px*1.2"
def pnl_hedge(lay,back):
    p=STAKE*(1-lay/back); return round(p*(1-COMM) if p>0 else p,2)
def latest(mid,mkt,sel,before=None):
    cur.execute(f"SELECT ts, back_px, lay_px, lay_sz FROM liq_sample WHERE market_id=%s AND mkt=%s AND sel=%s AND {SANE} AND ts>now()-interval '4 minutes' ORDER BY ts DESC LIMIT 1",(mid,mkt,sel)); return cur.fetchone()
def draw_jump_after(mid,ts):
    cur.execute(f"""WITH d AS (SELECT ts, back_px, lag(back_px) OVER (ORDER BY ts) pb, lag(lay_px) OVER (ORDER BY ts) pl FROM liq_sample WHERE market_id=%s AND mkt='MO' AND sel='DRAW' AND {SANE})
                    SELECT ts FROM d WHERE pb IS NOT NULL AND back_px>=pb*%s AND back_px>=pl*%s AND ts>%s ORDER BY ts LIMIT 1""",(mid,JUMP,JUMP,ts)); r=cur.fetchone(); return r[0] if r else None
def over_drop_after(mid,ts):
    cur.execute(f"""WITH d AS (SELECT ts, back_px, lag(back_px) OVER (ORDER BY ts) pb FROM liq_sample WHERE market_id=%s AND mkt='OU25' AND sel='OVER' AND {SANE})
                    SELECT ts FROM d WHERE pb IS NOT NULL AND back_px<=pb*0.7 AND ts>%s ORDER BY ts LIMIT 1""",(mid,ts)); r=cur.fetchone(); return r[0] if r else None
def back_at(mid,mkt,sel,ts):
    cur.execute(f"SELECT back_px, ts FROM liq_sample WHERE market_id=%s AND mkt=%s AND sel=%s AND ts>=%s AND {SANE} ORDER BY ts LIMIT 1",(mid,mkt,sel,ts)); return cur.fetchone()
def final_book(mid):
    cur.execute(f"""SELECT sel, back_px FROM liq_sample WHERE market_id=%s AND mkt='MO' AND back_px IS NOT NULL
                    AND ts=(SELECT max(ts) FROM liq_sample WHERE market_id=%s AND mkt='MO' AND sel='DRAW' AND {SANE} AND minute>=85)""",(mid,mid)); return {s:float(b) for s,b in cur.fetchall()}
def final_score(mid):
    cur.execute('SELECT hs, "as", minute FROM espn_stats WHERE market_id=%s AND hs IS NOT NULL ORDER BY ts DESC LIMIT 1',(mid,)); return cur.fetchone()
last_hb=0
while True:
    try:
        # ---- candidates: ESPN score/clock (<=3 min) joined to the latest xG row (<=4 min) on the same Betfair market
        cur.execute('''WITH e AS (SELECT DISTINCT ON (market_id) market_id, event_name, minute, period, hs, "as" FROM espn_stats WHERE market_id IS NOT NULL AND ts>now()-interval '3 minutes' ORDER BY market_id, ts DESC),
                            x AS (SELECT DISTINCT ON (market_id) market_id, h_xg, a_xg, league FROM ip_stats WHERE market_id IS NOT NULL AND h_xg IS NOT NULL AND ts>now()-interval '4 minutes' ORDER BY market_id, ts DESC)
                       SELECT e.market_id, e.event_name, e.minute, e.period, e.hs, e."as", x.h_xg, x.a_xg, x.league FROM e LEFT JOIN x USING (market_id)''')
        rows=cur.fetchall(); cands=len(rows); withxg=sum(1 for r in rows if r[6] is not None)
        for mid,ev,mn,per,hs,as_,hx,ax,lg in rows:
            if hx is None or mn is None or per!=2 or not (55<=mn<=78): continue
            hx,ax=float(hx),float(ax)
            # XG_DOM: level, xG gap >= 0.5 -> lay the side behind on xG at 5-30
            if hs==as_ and abs(hx-ax)>=0.5:
                out='AWAY' if hx>ax else 'HOME'; s=latest(mid,'MO',out)
                if s and s[2] is not None and 5.0<=float(s[2])<=30 and float(s[3] or 0)>=10:
                    cur.execute('INSERT INTO xg_paper (rule,market_id,event_name,competition,entry_ts,minute,mkt,sel,lay_px,lay_sz,hs,"as",h_xg,a_xg) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) ON CONFLICT DO NOTHING',
                                ('XG_DOM',mid,ev,lg,s[0],mn,'MO',out,s[2],s[3],hs,as_,hx,ax))
                    if cur.rowcount: print(f"XG_DOM lay {out} {ev} {mn}' {hs}-{as_} xG {hx:.2f}-{ax:.2f} @ {s[2]}",flush=True)
            # XG_OPEN: <=1 goal, xG total >= 1.0 -> lay Over 2.5 at 2.5-5
            if hs+as_<=1 and hx+ax>=1.0:
                s=latest(mid,'OU25','OVER')
                if s and s[2] is not None and 2.5<=float(s[2])<=5.0 and float(s[3] or 0)>=10:
                    cur.execute('INSERT INTO xg_paper (rule,market_id,event_name,competition,entry_ts,minute,mkt,sel,lay_px,lay_sz,hs,"as",h_xg,a_xg) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) ON CONFLICT DO NOTHING',
                                ('XG_OPEN',mid,ev,lg,s[0],mn,'OU25','OVER',s[2],s[3],hs,as_,hx,ax))
                    if cur.rowcount: print(f"XG_OPEN lay Over2.5 {ev} {mn}' {hs}-{as_} xG {hx:.2f}+{ax:.2f} @ {s[2]}",flush=True)
        # ---- exits
        cur.execute("SELECT id, rule, market_id, mkt, sel, lay_px, entry_ts FROM xg_paper WHERE exit_ts IS NULL")
        for pid,rule,mid,mkt,sel,lp,ets in cur.fetchall():
            lp=float(lp); now=datetime.datetime.now(datetime.timezone.utc)
            g=draw_jump_after(mid,ets) if rule=='XG_DOM' else (over_drop_after(mid,ets) or draw_jump_after(mid,ets))
            if g is not None:
                r=back_at(mid,mkt,sel,g+datetime.timedelta(seconds=120))
                if r:
                    pnl=pnl_hedge(lp,float(r[0])); cur.execute("UPDATE xg_paper SET goal_ts=%s, exit_ts=%s, exit_px=%s, exit_reason='GOAL', pnl_per_10=%s WHERE id=%s",(g,r[1],r[0],pnl,pid)); print(f"EXIT GOAL {rule} {mid} {lp}->{r[0]} {pnl:+.2f}",flush=True)
                continue
            if rule=='XG_OPEN' and now>=ets+datetime.timedelta(minutes=20):
                r=back_at(mid,mkt,sel,ets+datetime.timedelta(minutes=20))
                if r:
                    pnl=pnl_hedge(lp,float(r[0])); cur.execute("UPDATE xg_paper SET exit_ts=%s, exit_px=%s, exit_reason='T20', pnl_per_10=%s WHERE id=%s",(r[1],r[0],pnl,pid)); print(f"EXIT T20 {mid} {lp}->{r[0]} {pnl:+.2f}",flush=True); continue
            # market gone (no samples 20 min) -> settle
            cur.execute("SELECT 1 FROM liq_sample WHERE market_id=%s AND ts>now()-interval '20 minutes' LIMIT 1",(mid,))
            if cur.fetchone() or now<ets+datetime.timedelta(minutes=25): continue
            if rule=='XG_DOM':
                fin=final_book(mid)
                if not fin: continue
                w=min(fin,key=fin.get)
                if fin[w]>1.15: reason,pnl='UNKNOWN',None
                elif w==sel: reason,pnl='SETTLE_LOSS',round(-STAKE*(lp-1),2)
                else: reason,pnl='SETTLE_WIN',round(STAKE*(1-COMM),2)
            else:
                fs=final_score(mid)
                if not fs or fs[2] is None or fs[2]<85: reason,pnl='UNKNOWN',None
                elif fs[0]+fs[1]>=3: reason,pnl='SETTLE_LOSS',round(-STAKE*(lp-1),2)
                else: reason,pnl='SETTLE_WIN',round(STAKE*(1-COMM),2)
            cur.execute("UPDATE xg_paper SET exit_ts=now(), exit_reason=%s, pnl_per_10=%s WHERE id=%s",(reason,pnl,pid))
        if time.time()-last_hb>60:
            cur.execute("INSERT INTO xg_heartbeat VALUES (1,now(),%s,%s,(SELECT count(*) FROM xg_paper WHERE exit_ts IS NULL)) ON CONFLICT (id) DO UPDATE SET last_seen=now(), candidates=EXCLUDED.candidates, with_xg=EXCLUDED.with_xg, open_trades=EXCLUDED.open_trades",(cands,withxg)); last_hb=time.time()
        time.sleep(30)
    except Exception as e:
        print("loop",repr(e)[:200],flush=True); time.sleep(20)
        try: con=connect(); cur=con.cursor()
        except Exception: pass
PYFILE
python3 -m py_compile /root/pe-xg/xg_paper.py
cat > /root/pe-xg/keepalive.sh <<'SH'
#!/bin/bash
pgrep -f xg_paper.py >/dev/null || (cd /root/pe-xg && nohup python3 xg_paper.py >> xg.log 2>&1 &)
SH
chmod +x /root/pe-xg/keepalive.sh
( crontab -l 2>/dev/null | grep -v "pe-xg/keepalive" ; echo "* * * * * /root/pe-xg/keepalive.sh" ) | crontab -
/root/pe-xg/keepalive.sh; sleep 70; pgrep -af xg_paper.py | head -1; tail -3 /root/pe-xg/xg.log
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require').cursor()
c.execute("SELECT * FROM xg_heartbeat"); print("xg heartbeat (candidates, with_xg, open):",c.fetchall())
c.execute("SELECT * FROM ltd_control"); print("ltd_control:",c.fetchall())
c.execute("SELECT count(*) FROM ip_stats WHERE ts>now()-interval '10 minutes' AND h_xg IS NOT NULL"); print("xG rows last 10 min (expect 0 until the quota resets at midnight):",c.fetchone()[0])
PY
