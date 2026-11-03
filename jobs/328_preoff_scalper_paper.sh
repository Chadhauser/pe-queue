#!/bin/bash
# 328: RACING PRE-OFF SCALPER (Caan Berry / Peter Webb rules), PAPER, on the live stream. Builds /root/pe-race/preoff_scalp_paper.py
# + keepalive, starts it with nohup, and checks the heartbeat. Rules: UK/IE WIN, 30 s–10 min before the off, market matched >= £50k
# (sum of selection traded volume on the stream — a proxy, stated), runner 2.0–8.0, spread <= 2 ticks. Weight of money over 30 s at
# the touch (best-level sizes only — the stream carries sizes at the best price): >= 0.65 on the back side and last 3 traded prices
# not lengthening -> BACK at the touch; <= 0.35 and not shortening -> LAY at the touch. Exit: +2 ticks passive (filled only when the
# traded price goes THROUGH the level), -2 ticks stop at the touch, 60 s elapsed, or 30 s before the off. One position per runner,
# max 3 open. Paper only: no orders, no Betfair session. Table preoff_scalp_paper, heartbeat preoff_scalp_heartbeat.
mkdir -p /root/pe-race
cat > /root/pe-race/preoff_scalp_paper.py <<'PY'
import sys,time,datetime,psycopg2,psycopg2.extras
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("""CREATE TABLE IF NOT EXISTS preoff_scalp_paper (id SERIAL PRIMARY KEY, ts TIMESTAMPTZ, market_id TEXT, sel_id BIGINT, sel TEXT, side TEXT, entry_px NUMERIC, wom NUMERIC,
  secs_to_off INT, exit_ts TIMESTAMPTZ, exit_px NUMERIC, exit_reason TEXT, ticks INT, pnl_per_10 NUMERIC);
CREATE TABLE IF NOT EXISTS preoff_scalp_heartbeat (id INT PRIMARY KEY, last_seen TIMESTAMPTZ, open_positions INT, markets_watched INT);
INSERT INTO preoff_scalp_heartbeat VALUES (1, now(), 0, 0) ON CONFLICT (id) DO NOTHING""")
LADDER=[(1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)]
def tick(p):
    for lo,hi,t in LADDER:
        if lo<=p<hi: return t
    return 10
def step(p,n):
    p=float(p)
    for _ in range(abs(n)):
        p=round(p+tick(p if n>0 else p-1e-9)*(1 if n>0 else -1),2)
    return p
def ticks_between(a,b):
    # signed number of ladder ticks from a to b (+ = b higher)
    a=float(a); b=float(b); n=0; p=a
    if b>a:
        while p<b-1e-9 and n<200: p=step(p,1); n+=1
        return n
    while p>b+1e-9 and n<200: p=step(p,-1); n+=1
    return -n
open_pos={}   # (market_id,sel_id) -> dict
def pnl(side,p,q):
    p=float(p); q=float(q)
    r=10*(p/q-1) if side=='BACK' else 10*(1-p/q)
    return round(r*0.98 if r>0 else r,2)
def close(key,q,reason,now):
    o=open_pos.pop(key); r=pnl(o['side'],o['px'],q); tk=ticks_between(o['px'],q)*(-1 if o['side']=='BACK' else 1)
    cur.execute("UPDATE preoff_scalp_paper SET exit_ts=%s, exit_px=%s, exit_reason=%s, ticks=%s, pnl_per_10=%s WHERE id=%s",(now,q,reason,tk,r,o['id']))
    print(f"EXIT {o['sel']} {o['side']} {o['px']} -> {q} {reason} {r:+.2f}",flush=True)
while True:
    try:
        now=datetime.datetime.now(datetime.timezone.utc)
        cur.execute("""SELECT market_id, sel_id, sel, back_px::float, back_sz::float, lay_px::float, lay_sz::float, ltp::float, tv::float, secs_to_off, ts_recv
            FROM stream_ticks WHERE sport='racing' AND mkt='WIN' AND status='OPEN' AND inplay=false AND ts_recv>now()-interval '45 seconds'
            ORDER BY ts_recv""")
        rows=cur.fetchall()
        latest={}; hist={}
        for r in rows:
            k=(r[0],r[1]); latest[k]=r; hist.setdefault(k,[]).append(r)
        mkt_vol={}
        for k,r in latest.items(): mkt_vol[k[0]]=mkt_vol.get(k[0],0)+(r[8] or 0)
        # exits first
        for key in list(open_pos):
            o=open_pos[key]; r=latest.get(key)
            if not r:
                if (now-o['t']).total_seconds()>90: close(key,o['px'],'no_data',now)
                continue
            bp,lp,ltp,sto=r[3],r[5],r[7],r[9]
            if not bp or not lp: continue
            if o['side']=='BACK':
                tgt=step(o['px'],-2); stop=step(o['px'],2)
                if ltp and ltp<tgt: close(key,tgt,'target',now); continue          # traded THROUGH our passive lay
                if lp>=stop: close(key,lp,'stop',now); continue                       # lay at the touch to stop
            else:
                tgt=step(o['px'],2); stop=step(o['px'],-2)
                if ltp and ltp>tgt: close(key,tgt,'target',now); continue
                if bp<=stop: close(key,bp,'stop',now); continue
            if (now-o['t']).total_seconds()>=60: close(key, lp if o['side']=='BACK' else bp,'time',now); continue
            if sto is not None and sto<=30: close(key, lp if o['side']=='BACK' else bp,'pre_off',now); continue
        # entries
        if len(open_pos)<3:
            for key,r in latest.items():
                if key in open_pos or len(open_pos)>=3: continue
                mid,sid,sel,bp,bs,lp,ls,ltp,tv,sto,ts=r
                if not (bp and lp and sto is not None and 30<sto<=600): continue
                if not (2.0<=bp<=8.0) or mkt_vol.get(mid,0)<50000: continue
                if ticks_between(bp,lp)>2: continue
                h=[x for x in hist[key] if (now-x[10]).total_seconds()<=30 and x[4] and x[6]]
                if len(h)<5: continue
                wom=sum(x[4]/(x[4]+x[6]) for x in h)/len(h)
                lt=[x[7] for x in hist[key] if x[7]]; last3=lt[-3:]
                if len(last3)<3: continue
                lengthening=last3[0]<last3[1]<last3[2]; shortening=last3[0]>last3[1]>last3[2]
                side=None
                if wom>=0.65 and not lengthening: side,px='BACK',bp
                elif wom<=0.35 and not shortening: side,px='LAY',lp
                if not side: continue
                cur.execute("SELECT count(*) FROM preoff_scalp_paper WHERE market_id=%s AND sel_id=%s AND ts>now()-interval '90 seconds'",(mid,sid))
                if cur.fetchone()[0]: continue   # cool-down per runner
                cur.execute("INSERT INTO preoff_scalp_paper (ts,market_id,sel_id,sel,side,entry_px,wom,secs_to_off) VALUES (%s,%s,%s,%s,%s,%s,%s,%s) RETURNING id",(now,mid,sid,sel,side,px,round(wom,3),sto))
                open_pos[key]={'id':cur.fetchone()[0],'side':side,'px':px,'t':now,'sel':sel}
                print(f"ENTER {sel} {side} @{px} wom {wom:.2f} sto {sto}",flush=True)
        cur.execute("UPDATE preoff_scalp_heartbeat SET last_seen=now(), open_positions=%s, markets_watched=%s WHERE id=1",(len(open_pos),len(mkt_vol)))
    except Exception as e:
        print("ERR",str(e)[:200],flush=True)
        try: con.rollback()
        except Exception: pass
    time.sleep(2)
PY
python3 -m py_compile /root/pe-race/preoff_scalp_paper.py || exit 1
cat > /root/pe-race/keepalive_preoff_scalp.sh <<'SH'
#!/bin/bash
while true; do python3 /root/pe-race/preoff_scalp_paper.py >> /root/pe-race/preoff_scalp.log 2>&1; sleep 10; done
SH
chmod +x /root/pe-race/keepalive_preoff_scalp.sh
pgrep -f keepalive_preoff_scalp.sh >/dev/null || nohup /root/pe-race/keepalive_preoff_scalp.sh >/dev/null 2>&1 &
sleep 20; echo "== heartbeat"; python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
k=psycopg2.connect(DB,sslmode='require').cursor(); k.execute("SELECT last_seen, now()-last_seen age, open_positions, markets_watched FROM preoff_scalp_heartbeat"); print(k.fetchone())
PY
tail -5 /root/pe-race/preoff_scalp.log
