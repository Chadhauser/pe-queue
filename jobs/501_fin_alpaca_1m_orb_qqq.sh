#!/bin/bash
# 501: FINANCIAL — Alpaca 1-minute history (free IEX feed, 2016->) for QQQ TQQQ SQQQ SPY IWM TLT GLD USO, monthly parquet under
# /root/pe-data/alpaca (resumable; exit 75 = more months to fetch). Keys read from /root/pe-logger/.env via creds.py (Peter pasted
# them 2 Nov 06:41; never printed). Then ORB (Zarattini-Aziz, published on QQQ) rerun on the full QQQ history with the random-side
# control and the Topstep 50K Monte Carlo -> table orb_qqq_trades. Dukascopy daemon (281) left running for NQ but no longer the gate.
mkdir -p /root/pe-fin /root/pe-data/alpaca && cd /root/pe-fin
pip install -q requests pyarrow --break-system-packages 2>&1 | grep -v WARNING | tail -1
cat > alpaca_pull.py <<'PYFILE'
import os, sys, time, datetime, requests, pandas as pd
sys.path.insert(0,'/root/pe-queue/runner'); import creds
E=creds.all_vars(); K,S=E.get('ALPACA_KEY'),E.get('ALPACA_SECRET')
if not K or not S: print("NO ALPACA KEYS in env/.env files"); sys.exit(1)
H={'APCA-API-KEY-ID':K,'APCA-API-SECRET-KEY':S}; BASE='/root/pe-data/alpaca'
SYMS=['QQQ','TQQQ','SQQQ','SPY','IWM','TLT','GLD','USO']
START=datetime.date(2016,1,1); today=datetime.date.today(); first=(today.replace(day=1)-datetime.timedelta(days=1)).replace(day=1)
months=[]; m=first
while m>=START: months.append(m); m=(m-datetime.timedelta(days=1)).replace(day=1)
budget=time.time()+9000; unfinished=False
def fetch_month(sym,m0):
    m1=(m0.replace(day=28)+datetime.timedelta(days=4)).replace(day=1); frames=[]; tok=None
    while True:
        p={'symbols':sym,'timeframe':'1Min','start':f"{m0}T00:00:00Z",'end':f"{m1}T00:00:00Z",'limit':10000,'feed':'iex','adjustment':'all','sort':'asc'}
        if tok: p['page_token']=tok
        for a in range(5):
            r=requests.get('https://data.alpaca.markets/v2/stocks/bars',params=p,headers=H,timeout=60)
            if r.status_code==429: time.sleep(5+5*a); continue
            if r.status_code>=500: time.sleep(3); continue
            break
        if r.status_code!=200: print(sym,m0,"HTTP",r.status_code,r.text[:120]); return None
        j=r.json(); bars=(j.get('bars') or {}).get(sym) or []
        if bars: frames.append(pd.DataFrame(bars))
        tok=j.get('next_page_token')
        if not tok: break
        time.sleep(0.35)
    if not frames: return pd.DataFrame()
    b=pd.concat(frames); b['ts']=pd.to_datetime(b['t'],utc=True); b=b.set_index('ts').sort_index()
    b=b.rename(columns={'o':'open','h':'high','l':'low','c':'close','v':'volume','n':'ticks'})[['open','high','low','close','volume','ticks']]
    return b[~b.index.duplicated()]
for sym in SYMS:
    os.makedirs(f"{BASE}/{sym}",exist_ok=True); done=0; new=0
    for m0 in months:
        out=f"{BASE}/{sym}/1m_{m0:%Y-%m}.parquet"
        if os.path.exists(out): done+=1; continue
        if time.time()>budget: unfinished=True; break
        b=fetch_month(sym,m0)
        if b is None: unfinished=True; break
        b.to_parquet(out); done+=1; new+=1
        if new%12==1: print(sym,m0.strftime('%Y-%m'),"bars",len(b),flush=True)
    files=sorted(os.listdir(f"{BASE}/{sym}"))
    allb=pd.concat(pd.read_parquet(f"{BASE}/{sym}/{f}") for f in files) if files else pd.DataFrame()
    ny=allb.index.tz_convert('America/New_York') if len(allb) else None
    print(f"== {sym}: months {done}/{len(months)} (+{new} this run) | bars {len(allb)} | {allb.index[0] if len(allb) else '-'} -> {allb.index[-1] if len(allb) else '-'} | days {len(set(ny.date)) if len(allb) else 0} | RTH bars/day {((ny.hour*60+ny.minute>=570)&(ny.hour*60+ny.minute<960)).sum()/max(1,len(set(ny.date))) if len(allb) else 0:.0f}",flush=True)
    if unfinished: break
sys.exit(75 if unfinished else 0)
PYFILE
cat > alpaca_load.py <<'PYFILE'
import os, pandas as pd
BASE='/root/pe-data/alpaca'
def load(sym, spread=0.01):
    d=f"{BASE}/{sym}"; files=sorted(f for f in os.listdir(d) if f.endswith('.parquet')) if os.path.isdir(d) else []
    if not files: return pd.DataFrame(columns=['open','high','low','close','spread','ticks'])
    b=pd.concat(pd.read_parquet(f"{d}/{f}") for f in files).sort_index(); b=b[~b.index.duplicated()]
    b['spread']=spread; return b[['open','high','low','close','spread','ticks','volume']]
PYFILE
cat > orb_qqq.py <<'PYFILE'
import os, sys, math, numpy as np, pandas as pd
sys.path.insert(0,'/root/pe-fin'); from alpaca_load import load
b=load('QQQ'); ndays=len(np.unique(b.index.date)) if len(b) else 0
if ndays<380: print(f"only {ndays} trading days on disk — need 380"); sys.exit(0)
ny=b.index.tz_convert('America/New_York'); b=b.assign(d=ny.date,t=ny.time)
SPREAD=float(b.spread.mean()); SLIP=0.01; COST_PTS=SPREAD+2*SLIP   # QQQ: 1c spread + 1c slippage each side (dollars per share)
print(f"bars {len(b)} | {b.index[0]} -> {b.index[-1]} | mean spread {SPREAD:.3f} pts | round-trip cost {COST_PTS:.3f} pts")
import datetime as dt
T0,T1,TC=dt.time(9,30),dt.time(9,35),dt.time(16,0)
rows=[]
for d,g in b.groupby('d'):
    sess=g[(g.t>=T0)&(g.t<TC)]
    if len(sess)<300: continue
    fb=sess[(sess.t>=T0)&(sess.t<T1)]
    if len(fb)<3: continue
    o,c,hi,lo=fb.open.iloc[0],fb.close.iloc[-1],fb.high.max(),fb.low.min(); rng=hi-lo
    if rng<=0 or abs(c-o)<0.05*rng: continue
    side=1 if c>o else -1; rest=sess[sess.t>=T1]
    if not len(rest): continue
    entry=rest.open.iloc[0]; stop=lo if side>0 else hi; R=abs(entry-stop)
    if R<=0: continue
    target=entry+side*10*R; exit_px=rest.close.iloc[-1]; reason='close'
    for r in rest.itertuples():
        if side>0 and r.low<=stop: exit_px=stop; reason='stop'; break
        if side<0 and r.high>=stop: exit_px=stop; reason='stop'; break
        if side>0 and r.high>=target: exit_px=target; reason='target'; break
        if side<0 and r.low<=target: exit_px=target; reason='target'; break
    pts=side*(exit_px-entry)-COST_PTS; rows.append(dict(date=pd.Timestamp(d),side=side,R=R,pts=pts,r_mult=pts/R,reason=reason))
T=pd.DataFrame(rows).set_index('date'); n=len(T); mid=T.index[n//2]
def rep(x,label):
    if len(x)<20: print(label,'too few'); return
    r=x.r_mult; eq=(1+0.01*r).cumprod(); dd=((eq/eq.cummax())-1).min(); t=r.mean()/(r.std()/math.sqrt(len(r)))
    print(f"{label}: trades {len(r)} | win {100*(r>0).mean():.1f}% | mean R {r.mean():+.3f} | t {t:.2f} | Sharpe(ann, 1%/trade) {r.mean()/r.std()*math.sqrt(252):.2f} | maxDD @1% {100*dd:.1f}% | exits {x.reason.value_counts().to_dict()}")
print("\n=== ORB on QQQ as published (Zarattini-Aziz instrument), 1c spread + 1c slip, $ per share ==="); rep(T,'ALL'); rep(T[T.index<mid],'IS first half'); rep(T[T.index>=mid],'OOS second half')
print("by year:"); print(T.groupby(T.index.year).r_mult.agg(['count','mean',lambda s:(s>0).mean()]).round(3).to_string())
rng=np.random.default_rng(3); synth=T.copy(); synth['r_mult']=T.r_mult.values*rng.choice([-1,1],len(T))
print("\n=== synthetic (direction randomised) — must be ~0 ==="); rep(synth,'SYNTH')
# Monte Carlo vs Topstep 50K: $500 risk/trade (1%), $3,000 target, $2,000 trailing MLL from end-of-day balance high
oos=T[T.index>=mid].r_mult.values; res={'pass':0,'bust':0,'neither':0}
for _ in range(10000):
    seq=rng.choice(oos,size=len(oos),replace=True); bal=0.0; hi=0.0; out='neither'
    for r in seq:
        bal+=500*r
        if bal>=3000: out='pass'; break
        hi=max(hi,bal)
        if bal<=hi-2000: out='bust'; break
    res[out]+=1
print(f"\n=== Monte Carlo vs Topstep 50K ($500 risk, +$3k pass, $2k trailing MLL), 10k shuffles of {len(oos)} OOS trades: {res} ===")
print("expected pass rate by chance if mean R = 0 is roughly the same as bust rate; a real edge shows pass >> bust")
import psycopg2,psycopg2.extras; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("CREATE TABLE IF NOT EXISTS orb_qqq_trades (date DATE PRIMARY KEY, side INT, r_pts NUMERIC, pts NUMERIC, r_mult NUMERIC, reason TEXT)")
psycopg2.extras.execute_values(cur,"INSERT INTO orb_qqq_trades VALUES %s ON CONFLICT (date) DO UPDATE SET side=EXCLUDED.side,r_pts=EXCLUDED.r_pts,pts=EXCLUDED.pts,r_mult=EXCLUDED.r_mult,reason=EXCLUDED.reason",[(i.date(),int(r.side),float(round(r.R,3)),float(round(r.pts,3)),float(round(r.r_mult,4)),r.reason) for i,r in T.iterrows()])
print("stored orb_qqq_trades",n)
PYFILE
python3 -m py_compile alpaca_pull.py alpaca_load.py orb_qqq.py || exit 1
timeout 9500 python3 alpaca_pull.py; rc=$?; echo "pull exit $rc"
if [ $rc -eq 75 ]; then exit 75; fi
[ $rc -ne 0 ] && exit $rc
echo; echo "== ORB on QQQ, full history"; timeout 1500 python3 orb_qqq.py; echo "orb exit $?"
