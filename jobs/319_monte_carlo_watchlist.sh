#!/bin/bash
set -o pipefail
# 319: MONTE CARLO ON THE WATCH-LIST — what the three lines that are currently positive at real prices would do to a bank, if their
# recorded per-trade results are what they look like. Bootstrap 10,000 30-day paths from the real-price samples: T2 tennis
# (t2_paper, live key), HT 0-2 -> Over 2.5 (coach_tape, 27 Oct onward), racing book 10v1 (racing_mm_paper, book 10v1). Trades per
# day = observed rate. Stakes £2 / £10 / £50 (lay liability equivalent). Reports: expected 30-day P&L, 5th/95th percentile, worst
# drawdown, probability of a losing month, and the sample size each line would need for t>=3.5 at its current mean. Also the
# combined book. This is a sizing tool, not evidence: the inputs are UNVERIFIED small samples and it says so.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require')
lines={}
t2=pd.read_sql("SELECT ts::date d, p_settle::float pnl FROM t2_paper WHERE ts>='2026-10-27' AND p_settle IS NOT NULL",con); lines['T2 tennis (hold to settle)']=t2
ht=pd.read_sql("SELECT tape_date d, pnl10::float pnl FROM coach_tape WHERE line='HT_0_2_O25' AND pnl10 IS NOT NULL",con); lines['HT 0-2 -> back Over 2.5']=ht
mm=pd.read_sql("SELECT quoted_ts::date d, pnl_per_10::float pnl FROM racing_mm_paper WHERE pnl_per_10 IS NOT NULL AND quoted_ts>='2026-10-29'",con)
try:
    b=pd.read_sql("SELECT quoted_ts::date d, pnl_per_10::float pnl FROM racing_mm_paper WHERE pnl_per_10 IS NOT NULL AND book='10v1'",con)
    if len(b): mm=b
except Exception: con.rollback()
lines['Racing book 10v1 (per round)']=mm
rng=np.random.default_rng(1); N=10000; DAYS=30
print(f"Bootstrap {N} x {DAYS}-day paths per line. Per £10 risk. UNVERIFIED inputs (small samples). Needed-n = trades for t>=3.5 at the observed mean/sd.\n")
rows=[]; combined=np.zeros((N,DAYS))
for name,df in lines.items():
    if len(df)<20: print(f"{name}: only {len(df)} samples — skipped"); continue
    x=df.pnl.values; days=max(1,df.d.nunique()); rate=len(x)/days; mu=x.mean(); sd=x.std(ddof=1); need=int(np.ceil((3.5*sd/mu)**2)) if mu>0 else None
    paths=np.zeros((N,DAYS))
    for di in range(DAYS):
        k=rng.poisson(rate,N)
        for i in np.unique(k):
            idx=np.where(k==i)[0]
            if i==0: continue
            paths[idx,di]=rng.choice(x,size=(len(idx),i)).sum(axis=1)
    combined+=paths
    cum=paths.cumsum(axis=1); tot=cum[:,-1]; dd=(np.maximum.accumulate(cum,axis=1)-cum).max(axis=1)
    for stake in (2,10,50):
        f=stake/10
        rows.append((name,stake,round(rate,1),round(mu,2),round(tot.mean()*f,0),round(np.percentile(tot,5)*f,0),round(np.percentile(tot,95)*f,0),round(dd.mean()*f,0),round((tot<0).mean()*100,0),need,len(x)))
cum=combined.cumsum(axis=1); tot=cum[:,-1]; dd=(np.maximum.accumulate(cum,axis=1)-cum).max(axis=1)
for stake in (2,10,50):
    f=stake/10; rows.append(('COMBINED',stake,None,None,round(tot.mean()*f,0),round(np.percentile(tot,5)*f,0),round(np.percentile(tot,95)*f,0),round(dd.mean()*f,0),round((tot<0).mean()*100,0),None,None))
R=pd.DataFrame(rows,columns=['line','stake £','trades/day','mean/£10','exp 30d £','p5 £','p95 £','avg max DD £','P(lose month) %','needed n','n now'])
print(R.to_string(index=False))
print("\nReading: 'needed n' is how many real-price trades the line must accumulate at its current mean before it is statistically an edge; 'n now' is how many it has.")
PY
