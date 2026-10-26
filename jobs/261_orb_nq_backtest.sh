#!/bin/bash
# 261 (repush of 231, which ran before 240 wrote duka_load.py): FINANCIAL — Zarattini-Aziz 5-minute OPENING RANGE BREAKOUT on the Nasdaq-100 CFD (NQ proxy), coded exactly as published:
#   first 5-min bar 09:30-09:35 ET sets direction (skip doji: |close-open| < 5% of bar range); enter at 09:35 open in that direction;
#   stop = first bar's low (long) / high (short); target = 10R; else flat at 16:00 ET close; one trade per day; risk 1% of equity.
# Costs: real mean spread from the Dukascopy bars (crossed once per side) + 1 index point slippage per side, both charged in points.
# Split: first 12 months IS / rest OOS (only 2 years exist — scope stated); report R per trade, win rate, Sharpe, max DD, t-stat,
# and a synthetic test (same bars, direction randomised) that must give ~0 R per trade. Then a Monte Carlo of the OOS R-sequence
# against Topstep 50K rules: $2,000 trailing max-loss (end-of-day trailing, breached intraday), $3,000 target, 1% = $500 risk per
# trade -> probability of passing vs busting over 10,000 shuffles. Waits for >=18 months of 230's parquet (exit 75 = re-poll).
cd /root/pe-fin || exit 1
cat > orb_nq.py <<'PYFILE'
import os, sys, math, numpy as np, pandas as pd
sys.path.insert(0,'/root/pe-fin'); from duka_load import load
b=load('USATECHIDXUSD'); ndays=len(np.unique(b.index.date)) if len(b) else 0
if ndays<380: print(f"only {ndays} trading days on disk — waiting (need 380 = ~18 months)"); sys.exit(75)
ny=b.index.tz_convert('America/New_York'); b=b.assign(d=ny.date,t=ny.time)
SPREAD=float(b.spread.mean()); SLIP=1.0; COST_PTS=SPREAD+2*SLIP   # spread crossed once over the round trip + 1pt slippage each side
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
print("\n=== ORB as published, real spread + 1pt slippage ==="); rep(T,'ALL'); rep(T[T.index<mid],'IS first half'); rep(T[T.index>=mid],'OOS second half')
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
cur.execute("CREATE TABLE IF NOT EXISTS orb_trades (date DATE PRIMARY KEY, side INT, r_pts NUMERIC, pts NUMERIC, r_mult NUMERIC, reason TEXT)")
psycopg2.extras.execute_values(cur,"INSERT INTO orb_trades VALUES %s ON CONFLICT (date) DO UPDATE SET side=EXCLUDED.side,r_pts=EXCLUDED.r_pts,pts=EXCLUDED.pts,r_mult=EXCLUDED.r_mult,reason=EXCLUDED.reason",[(i.date(),int(r.side),float(round(r.R,3)),float(round(r.pts,3)),float(round(r.r_mult,4)),r.reason) for i,r in T.iterrows()])
print("stored orb_trades",n)
PYFILE
python3 -m py_compile orb_nq.py || exit 1
timeout 1500 python3 orb_nq.py; rc=$?; echo "exit $rc"; exit $rc
