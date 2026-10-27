#!/bin/bash
# 272 (fixes 269: reserved word window -> win_start; proper random-side control). PRELIMINARY FVT run at >=250 trading days (~12 months) so a first number exists today; the full 380-day run (261/263) follows automatically.
# Every number from this job is labelled PRELIMINARY / UNVERIFIED — half-sample IS/OOS of ~6 months each.
# 263: JJ SIMON "FAIR VALUE THEORY" on the NQ proxy, coded as published with the two discretionary parts made mechanical:
#  windows 09:30-11:00 and 14:00-15:00 ET on 1-min bars; fair value = window open price
#  phase A (first 15 min): CONTINUATION — enter in the direction price has moved from fair value when a displacement bar closes
#     (bar range >= 1.5x the 20-bar ATR, counter-wick < 20% of range, close beyond the prior 5-bar high/low = structure break)
#  phase B (rest of window): MEAN REVERSION — same displacement+break trigger but only when it points BACK toward fair value and
#     price is at least 1 ATR away from it
#  stop by ATR tier (ATR>20: 50pts, 7-20: 25pts, <7: 16.5pts), target 1.5R, no management, max 1 trade per window, flat at window end
#  costs: real mean spread + 1pt slippage per side. IS first half / OOS second half, direction-randomised synthetic, Topstep 50K Monte Carlo.
cd /root/pe-fin || exit 1
cat > fvt_nq.py <<'PYFILE'
import sys, math, numpy as np, pandas as pd, datetime as dt
sys.path.insert(0,'/root/pe-fin'); from duka_load import load
b=load('USATECHIDXUSD'); ndays=len(np.unique(b.index.date)) if len(b) else 0
if ndays<240: print(f"only {ndays} trading days — waiting"); sys.exit(75)
ny=b.index.tz_convert('America/New_York'); b=b.assign(d=ny.date,t=ny.time)
SPREAD=float(b.spread.mean()); COST=SPREAD+2.0
tr=pd.concat([b.high-b.low,(b.high-b.close.shift()).abs(),(b.low-b.close.shift()).abs()],axis=1).max(axis=1); b['atr']=tr.rolling(20).mean()
b['hi5']=b.high.rolling(5).max().shift(1); b['lo5']=b.low.rolling(5).min().shift(1)
WINS=[(dt.time(9,30),dt.time(11,0)),(dt.time(14,0),dt.time(15,0))]
def tier(atr): return 50.0 if atr>20 else (25.0 if atr>=7 else 16.5)
def simulate(random_side=False, seed=5):
    rng=np.random.default_rng(seed); rows=[]
    for d,g in b.groupby('d'):
        for w0,w1 in WINS:
            w=g[(g.t>=w0)&(g.t<w1)]
            if len(w)<60: continue
            fv=float(w.open.iloc[0]); t_phase=(pd.Timestamp.combine(pd.Timestamp(d),w0)+pd.Timedelta(minutes=15)).time()
            taken=False
            for r in w.itertuples():
                if taken or np.isnan(r.atr) or r.atr<=0: continue
                rng=r.high-r.low
                if rng<1.5*r.atr: continue
                up=r.close>r.open; wick=(r.high-max(r.open,r.close)) if up else (min(r.open,r.close)-r.low)
                if wick>0.2*rng: continue
                brk_up=r.close>r.hi5; brk_dn=r.close<r.lo5
                if not (brk_up or brk_dn): continue
                side=1 if brk_up else -1
                if random_side: side=int(rng.choice([-1,1]))
                if r.t<t_phase:   # continuation: trade must point away from fair value in the direction price already moved
                    if (r.close-fv)*side<=0: continue
                else:             # reversion: must point back toward fair value, from at least 1 ATR away
                    if (r.close-fv)*side>=0 or abs(r.close-fv)<r.atr: continue
                after=w[w.index>r.Index]
                if not len(after): continue
                entry=float(after.open.iloc[0]); R=tier(r.atr); stop=entry-side*R; target=entry+side*1.5*R
                exit_px=float(after.close.iloc[-1]); reason='window_end'
                for q in after.itertuples():
                    if side>0 and q.low<=stop or side<0 and q.high>=stop: exit_px=stop; reason='stop'; break
                    if side>0 and q.high>=target or side<0 and q.low<=target: exit_px=target; reason='target'; break
                pts=side*(exit_px-entry)-COST; rows.append(dict(date=pd.Timestamp(d),window=w0.strftime('%H:%M'),phase='cont' if r.t<t_phase else 'rev',side=side,R=R,pts=pts,r_mult=pts/R,reason=reason)); taken=True
    return pd.DataFrame(rows).set_index('date').sort_index()
T=simulate(); n=len(T)
if n<50: print('too few trades',n); sys.exit(0)
mid=T.index[n//2]
def rep(x,label):
    if len(x)<20: print(label,'too few'); return
    r=x.r_mult; t=r.mean()/(r.std()/math.sqrt(len(r))); eq=(1+0.01*r).cumprod(); dd=((eq/eq.cummax())-1).min()
    print(f"{label}: trades {len(r)} | win {100*(r>0).mean():.1f}% | mean R {r.mean():+.3f} | t {t:.2f} | maxDD@1% {100*dd:.1f}% | exits {x.reason.value_counts().to_dict()}")
print(f"spread {SPREAD:.3f} | round-trip cost {COST:.3f} pts | days {ndays}")
print("PRELIMINARY — ~12 months, halves of ~6 months; UNVERIFIED")
print("\n=== FVT mechanical ==="); rep(T,'ALL'); rep(T[T.index<mid],'IS'); rep(T[T.index>=mid],'OOS')
for k,g in T.groupby('phase'): rep(g,f'phase {k}')
for k,g in T.groupby('window'): rep(g,f'window {k}')
S=simulate(random_side=True, seed=17); print("\n=== CONTROL: random entry side, same triggers/stops/targets/costs ==="); rep(S,'CONTROL')
rng=np.random.default_rng(5)
oos=T[T.index>=mid].r_mult.values; res={'pass':0,'bust':0,'neither':0}
for _ in range(10000):
    seq=rng.choice(oos,size=len(oos),replace=True); bal=hi=0.0; out='neither'
    for r in seq:
        bal+=500*r
        if bal>=3000: out='pass'; break
        hi=max(hi,bal)
        if bal<=hi-2000: out='bust'; break
    res[out]+=1
print(f"\n=== Monte Carlo vs Topstep 50K ($500 risk/trade): {res} ===")
import psycopg2,psycopg2.extras; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("CREATE TABLE IF NOT EXISTS fvt_trades (date DATE, win_start TEXT, phase TEXT, side INT, r_pts NUMERIC, pts NUMERIC, r_mult NUMERIC, reason TEXT, UNIQUE(date,win_start))")
psycopg2.extras.execute_values(cur,"INSERT INTO fvt_trades VALUES %s ON CONFLICT (date,win_start) DO NOTHING",[(i.date(),r.window,r.phase,int(r.side),float(r.R),float(round(r.pts,3)),float(round(r.r_mult,4)),r.reason) for i,r in T.iterrows()])
print("stored fvt_trades",n)
PYFILE
python3 -m py_compile fvt_nq.py || exit 1
timeout 1500 python3 fvt_nq.py; rc=$?; echo "exit $rc"; exit $rc
