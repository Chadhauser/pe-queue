#!/bin/bash
# 264: OVERNIGHT vs INTRADAY index return split (Kelly & Clark 2011; Boyarchenko et al 2023 — VERIFIED to exist, net-of-cost UNVERIFIED).
# Rule: long the index from the 16:00 ET cash close to the 09:30 ET open (overnight leg) vs long 09:30->16:00 (day leg), every day.
# Data: yfinance 1h bars, 730 days, ES/NQ/YM/RTY/GC/CL (futures trade overnight so both legs are observable).
# Costs: 0.03% per side per leg (two trades a day). Reports mean/t per leg, IS/OOS halves, weekday split, and a random-sign control.
mkdir -p /root/pe-factory/v4 && cd /root/pe-factory/v4
cat > overnight.py <<'PYFILE'
import math, warnings, numpy as np, pandas as pd, yfinance as yf, datetime as dt
warnings.filterwarnings('ignore'); COST=0.0003
def legs(t):
    df=yf.download(t,period='730d',interval='1h',progress=False,auto_adjust=True,threads=False)
    if isinstance(df.columns,pd.MultiIndex): df.columns=df.columns.get_level_values(0)
    df=df.dropna(subset=['Close']); df.index=pd.to_datetime(df.index,utc=True).tz_convert('America/New_York')
    d=df.assign(date=df.index.date,hr=df.index.hour)
    o=d[d.hr==9].groupby('date').Close.first()      # first bar at/after 09:30 ET close ~ 10:00 proxy; use the 09:xx bar OPEN instead
    o=d[d.hr==9].groupby('date').Open.first(); c=d[d.hr==15].groupby('date').Close.last()
    x=pd.DataFrame({'open':o,'close':c}).dropna(); x['prev_close']=x.close.shift(1)
    x['overnight']=x.open/x.prev_close-1-2*COST; x['day']=x.close/x.open-1-2*COST
    return x.dropna()
def rep(s,label):
    if len(s)<100: print(label,'too few'); return
    t=s.mean()/(s.std()/math.sqrt(len(s))); print(f"  {label}: n {len(s)} | mean {s.mean()*1e4:+.1f} bp/day | ann {s.mean()*252*100:+.1f}% | t {t:+.2f} | sharpe {s.mean()/s.std()*math.sqrt(252):+.2f}")
rng=np.random.default_rng(2)
for tk in ('ES=F','NQ=F','YM=F','RTY=F','GC=F','CL=F'):
    try: x=legs(tk)
    except Exception as e: print(tk,'ERR',repr(e)[:80]); continue
    mid=x.index[len(x)//2]; print(f"\n== {tk}: {x.index[0]} -> {x.index[-1]} days {len(x)}")
    for leg in ('overnight','day'):
        rep(x[leg],f"{leg} ALL"); rep(x[leg][x.index<mid],f"{leg} IS"); rep(x[leg][x.index>=mid],f"{leg} OOS")
    wd=pd.Series(pd.to_datetime(x.index).dayofweek,index=x.index)
    print("  overnight by weekday (bp/day):",{int(k):round(v*1e4,1) for k,v in x.overnight.groupby(wd).mean().items()})
    rep(pd.Series(x.overnight.values*rng.choice([-1,1],len(x)),index=x.index),"overnight RANDOM-SIGN control")
print("\nVERDICT RULE: overnight leg needs t>=2.5 in BOTH halves after costs to go to forward paper; a day leg that is significantly negative is the same information (short the day).")
PYFILE
python3 -m py_compile overnight.py && timeout 900 python3 overnight.py 2>&1 | grep -v Warning
