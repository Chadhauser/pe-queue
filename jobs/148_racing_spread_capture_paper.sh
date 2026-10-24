#!/bin/bash
# 148: RACING SPREAD-CAPTURE PAPER BOT (market-making, the Caan Berry scalp automated). Reads the 1-second tape the swing recorder
# writes (no extra Betfair calls). Top-2 runners, last 8 minutes to 20 s before the off, spread >= 2 ticks: rest a BACK one tick
# inside the lay touch and a LAY one tick inside the back touch (earn the spread, never pay it). A side fills when LTP trades
# at/through it. Both filled = spread captured (ticks between). One side filled: keep the other resting; if 45 s pass or the price
# moves 3 ticks against, close at the touch (STOP). Inventory: one open position per runner, max 2 per race. Flat at -20 s.
# Every order and fill -> racing_mm_paper; nightly summary printed by the queue. Nothing live; verdict after 200 completed rounds.
mkdir -p /root/pe-race && cat > /root/pe-race/race_mm.py <<'PYFILE'
import sys, time, datetime, psycopg2, psycopg2.extras
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
LAD=[(1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)]
def tick(p):
    for lo,hi,s in LAD:
        if p<hi: return s
    return 10
def rnd(p): s=tick(p); return round(round(p/s)*s,2)
def up(p): return rnd(p+tick(p)+1e-9)
def down(p): return rnd(p-tick(p-1e-9)+1e-9) if p>1.01 else 1.01
def nticks(a,b):
    n=0; p=a
    if b>a:
        while p<b-1e-9 and n<500: p=up(p); n+=1
        return n
    while p>b+1e-9 and n<500: p=down(p); n+=1
    return -n
WINDOW=480; FLAT_AT=20; MIN_SPREAD=2; HOLD_MAX=45; STOP_TICKS=3; STAKE=10.0; COMM=0.02
def pnl_back_lay(bk,ly):   # back at bk, lay at ly, hedged, per £10 back stake
    p=STAKE*(bk/ly-1); return round(p*(1-COMM) if p>0 else p,2)
def connect():
    c=psycopg2.connect(DB,sslmode='require'); c.autocommit=True; return c
con=connect(); cur=con.cursor()
cur.execute("""CREATE TABLE IF NOT EXISTS racing_mm_paper (id SERIAL PRIMARY KEY, market_id TEXT, venue TEXT, race TEXT, market_start TIMESTAMPTZ, sel_id BIGINT, sel_name TEXT, rank INT,
  quoted_ts TIMESTAMPTZ, quoted_sto INT, spread_ticks INT, back_px NUMERIC, lay_px NUMERIC, first_side TEXT, first_fill_ts TIMESTAMPTZ, second_fill_ts TIMESTAMPTZ,
  exit_px NUMERIC, exit_ts TIMESTAMPTZ, exit_reason TEXT, ticks NUMERIC, pnl_per_10 NUMERIC);
CREATE TABLE IF NOT EXISTS racing_mm_heartbeat (id INT PRIMARY KEY, last_seen TIMESTAMPTZ, open_quotes INT, rounds_today INT)""")
quotes={}   # (mid,sid) -> dict
per_mkt={}; last_ts=None; last_hb=0; seen_close=set()
while True:
    try:
        cur.execute("""SELECT ts, market_id, venue, race, market_start, secs_to_off, status, sel_id, sel_name, rank, ltp::float, back_px::float, lay_px::float
                       FROM racing_tape WHERE ts > now()-interval '4 seconds' AND rank<=2 ORDER BY ts""")
        rows=cur.fetchall()
        now=datetime.datetime.now(datetime.timezone.utc)
        for ts,mid,venue,race,mstart,sto,st,sid,name,rank,ltp,bp,lp in rows:
            if last_ts is not None and ts<=last_ts: continue
            key=(mid,sid)
            if bp is None or lp is None or ltp is None: continue
            q=quotes.get(key)
            if q:
                # ---- manage existing quote
                if st!='OPEN' or sto<=FLAT_AT:
                    if q['first'] is None:
                        cur.execute("UPDATE racing_mm_paper SET exit_reason='UNFILLED', pnl_per_10=0, exit_ts=%s WHERE id=%s",(ts,q['id'])); quotes.pop(key); continue
                    # close inventory at the touch
                    x = lp if q['first']=='BACK' else bp
                    tk = -nticks(q['bk'],x) if q['first']=='BACK' else nticks(q['ly'],x)
                    pnl = pnl_back_lay(q['bk'],x) if q['first']=='BACK' else pnl_back_lay(x,q['ly'])
                    cur.execute("UPDATE racing_mm_paper SET exit_px=%s, exit_ts=%s, exit_reason=%s, ticks=%s, pnl_per_10=%s WHERE id=%s",(x,ts,'FLAT_PRE_OFF' if st=='OPEN' else 'MARKET_'+str(st),tk,pnl,q['id'])); quotes.pop(key); continue
                if q['first'] is None:
                    if ltp>=q['bk']-1e-9:   # our back got hit
                        q['first']='BACK'; q['t1']=ts; cur.execute("UPDATE racing_mm_paper SET first_side='BACK', first_fill_ts=%s WHERE id=%s",(ts,q['id']))
                    elif ltp<=q['ly']+1e-9:
                        q['first']='LAY'; q['t1']=ts; cur.execute("UPDATE racing_mm_paper SET first_side='LAY', first_fill_ts=%s WHERE id=%s",(ts,q['id']))
                    elif (ts-q['t0']).total_seconds()>60 or nticks(bp,lp)<MIN_SPREAD:   # stale quote: pull it
                        cur.execute("UPDATE racing_mm_paper SET exit_reason='PULLED', pnl_per_10=0, exit_ts=%s WHERE id=%s",(ts,q['id'])); quotes.pop(key)
                    continue
                # one side filled — does the other side fill?
                if q['first']=='BACK' and ltp<=q['ly']+1e-9:
                    tk=-nticks(q['bk'],q['ly']); pnl=pnl_back_lay(q['bk'],q['ly'])
                    cur.execute("UPDATE racing_mm_paper SET second_fill_ts=%s, exit_px=%s, exit_ts=%s, exit_reason='CAPTURED', ticks=%s, pnl_per_10=%s WHERE id=%s",(ts,q['ly'],ts,tk,pnl,q['id'])); quotes.pop(key); print(f"CAPTURED {venue} {race} {name} back {q['bk']} lay {q['ly']} {pnl:+.2f}",flush=True); continue
                if q['first']=='LAY' and ltp>=q['bk']-1e-9:
                    tk=-nticks(q['bk'],q['ly']); pnl=pnl_back_lay(q['bk'],q['ly'])
                    cur.execute("UPDATE racing_mm_paper SET second_fill_ts=%s, exit_px=%s, exit_ts=%s, exit_reason='CAPTURED', ticks=%s, pnl_per_10=%s WHERE id=%s",(ts,q['bk'],ts,tk,pnl,q['id'])); quotes.pop(key); print(f"CAPTURED {venue} {race} {name} lay {q['ly']} back {q['bk']} {pnl:+.2f}",flush=True); continue
                # stop / timeout on inventory
                held=(ts-q['t1']).total_seconds()
                if q['first']=='BACK':
                    x=lp; adverse=nticks(q['bk'],x)      # price drifted up = bad for a back
                    if adverse>=STOP_TICKS or held>HOLD_MAX:
                        pnl=pnl_back_lay(q['bk'],x); cur.execute("UPDATE racing_mm_paper SET exit_px=%s, exit_ts=%s, exit_reason=%s, ticks=%s, pnl_per_10=%s WHERE id=%s",(x,ts,'STOP' if adverse>=STOP_TICKS else 'TIMEOUT',-adverse,pnl,q['id'])); quotes.pop(key)
                else:
                    x=bp; adverse=-nticks(q['ly'],x)     # price shortened = bad for a lay
                    if adverse>=STOP_TICKS or held>HOLD_MAX:
                        pnl=pnl_back_lay(x,q['ly']); cur.execute("UPDATE racing_mm_paper SET exit_px=%s, exit_ts=%s, exit_reason=%s, ticks=%s, pnl_per_10=%s WHERE id=%s",(x,ts,'STOP' if adverse>=STOP_TICKS else 'TIMEOUT',-adverse,pnl,q['id'])); quotes.pop(key)
                continue
            # ---- new quote?
            if st!='OPEN' or sto>WINDOW or sto<=FLAT_AT+5: continue
            if per_mkt.get(mid,0)>=2 or any(k[0]==mid and quotes[k]['first'] is not None for k in quotes): continue
            sp=nticks(bp,lp)
            if sp<MIN_SPREAD: continue
            bk=down(lp); ly=up(bp)            # back one tick inside lay touch; lay one tick inside back touch
            if bk<=ly: continue                # need at least one tick between our two prices
            cur.execute("INSERT INTO racing_mm_paper (market_id,venue,race,market_start,sel_id,sel_name,rank,quoted_ts,quoted_sto,spread_ticks,back_px,lay_px) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) RETURNING id",
                        (mid,venue,race,mstart,sid,name,rank,ts,sto,sp,bk,ly))
            quotes[key]={'id':cur.fetchone()[0],'bk':bk,'ly':ly,'first':None,'t0':ts,'t1':None}; per_mkt[mid]=per_mkt.get(mid,0)+1
        if rows: last_ts=max(r[0] for r in rows)
        # forget finished markets
        for mid in [m for m in per_mkt if not any(k[0]==m for k in quotes)]:
            pass
        if time.time()-last_hb>30:
            cur.execute("INSERT INTO racing_mm_heartbeat VALUES (1,now(),%s,(SELECT count(*) FROM racing_mm_paper WHERE quoted_ts::date=current_date AND exit_reason IS NOT NULL)) ON CONFLICT (id) DO UPDATE SET last_seen=now(), open_quotes=EXCLUDED.open_quotes, rounds_today=EXCLUDED.rounds_today",(len(quotes),)); last_hb=time.time()
            if len(per_mkt)>500: per_mkt={m:c for m,c in per_mkt.items() if any(k[0]==m for k in quotes)}
        time.sleep(1)
    except Exception as e:
        print("loop",repr(e)[:200],flush=True); time.sleep(5)
        try: con=connect(); cur=con.cursor()
        except Exception: pass
PYFILE
python3 -m py_compile /root/pe-race/race_mm.py || exit 1
# unit test of the P&L and tick logic
python3 - <<'PY'
import importlib.util,sys
src=open('/root/pe-race/race_mm.py').read().split("def connect():")[0]; ns={}; exec(src,ns)
assert ns['nticks'](2.00,2.04)==2 and ns['down'](2.04)==2.02 and ns['up'](2.00)==2.02
p=ns['pnl_back_lay'](2.04,2.02); assert round(p,2)==round(10*(2.04/2.02-1)*0.98,2), p
print("tick/pnl tests PASS: back 2.04 lay 2.02 per £10 =",p)
PY
cat > /root/pe-race/keepalive_mm.sh <<'SH'
#!/bin/bash
pgrep -f race_mm.py >/dev/null || (cd /root/pe-race && nohup python3 race_mm.py >> mm.log 2>&1 &)
SH
chmod +x /root/pe-race/keepalive_mm.sh
( crontab -l 2>/dev/null | grep -v keepalive_mm ; echo "* * * * * /root/pe-race/keepalive_mm.sh" ) | crontab -
/root/pe-race/keepalive_mm.sh; sleep 20; pgrep -af race_mm.py; tail -5 /root/pe-race/mm.log
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require').cursor()
c.execute("SELECT count(*), max(ts) FROM racing_tape WHERE ts>now()-interval '10 minutes'"); print("tape rows last 10 min / latest:",c.fetchone())
c.execute("SELECT * FROM racing_mm_heartbeat"); print("mm heartbeat:",c.fetchall())
PY
