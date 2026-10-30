#!/bin/bash
# 282: NQ STATE SCAN on hourly bars (runs tonight, no download needed) — the stage-2 method that found the football edges, applied to
# one liquid instrument. No strategy assumed. Every bar: STATE = (hour ET, position of price vs session open in ATR units, session
# range-so-far in ATR units, day-of-week, 20-bar vol regime tercile) -> OUTCOME = next 1/2/4-bar return in points.
# Report every state cell with n>=60 where mean outcome differs from 0 by t>=3.0 AFTER a cost of spread+slippage, both halves of the
# sample agreeing in sign, and compare the count against chance. Also run the whole scan on a sign-shuffled copy (control).
# Instruments: NQ, ES, GC, CL hourly 730d (yfinance). Stores v4_state_scan.
mkdir -p /root/pe-factory/v4 && cd /root/pe-factory/v4
cat > state_scan.py <<'PYFILE'
import math, warnings, itertools, numpy as np, pandas as pd, yfinance as yf, datetime as dt
warnings.filterwarnings('ignore'); pd.set_option('display.width',250)
COST={'NQ=F':2.5,'ES=F':0.75,'GC=F':0.5,'CL=F':0.04}   # round trip points: spread + 1 tick slippage per side (conservative)
from math import erf,sqrt
pn=lambda x:0.5*(1+erf(x/sqrt(2)))
allrows=[]
for tk in COST:
    df=yf.download(tk,period='730d',interval='1h',progress=False,auto_adjust=True,threads=False)
    if isinstance(df.columns,pd.MultiIndex): df.columns=df.columns.get_level_values(0)
    df=df.dropna(subset=['Close']); df.index=pd.to_datetime(df.index,utc=True).tz_convert('America/New_York')
    df['date']=df.index.date; df['hr']=df.index.hour; df['dow']=df.index.dayofweek
    tr=pd.concat([df.High-df.Low,(df.High-df.Close.shift()).abs(),(df.Low-df.Close.shift()).abs()],axis=1).max(axis=1); df['atr']=tr.rolling(24).mean()
    sess=df[(df.hr>=9)&(df.hr<16)].copy()
    sess['sopen']=sess.groupby('date').Open.transform('first'); sess['shi']=sess.groupby('date').High.cummax(); sess['slo']=sess.groupby('date').Low.cummin()
    sess['pos']=((sess.Close-sess.sopen)/sess.atr).round(0).clip(-3,3); sess['rng']=((sess.shi-sess.slo)/sess.atr).round(0).clip(0,4)
    vol20=sess.Close.pct_change().rolling(20).std(); sess['vreg']=pd.qcut(vol20.rank(method='first'),3,labels=[0,1,2])
    for h in (1,2,4): sess[f'fwd{h}']=sess.Close.shift(-h)-sess.Close
    sess=sess.dropna(subset=['atr','fwd4','vreg']); mid=sess.index[len(sess)//2]
    def scan(data,label):
        rows=[]
        for keys,g in data.groupby(['hr','pos','rng','dow','vreg']):
            if len(g)<60: continue
            for h in (1,2,4):
                x=g[f'fwd{h}']; m=x.mean(); side=1 if m>0 else -1; net=side*x-COST[tk]
                t=net.mean()/(net.std()/math.sqrt(len(net))) if net.std()>0 else 0
                a=g[g.index<mid][f'fwd{h}']; b=g[g.index>=mid][f'fwd{h}']
                rows.append(dict(tk=tk,hr=keys[0],pos=keys[1],rng=keys[2],dow=keys[3],vreg=int(keys[4]),hold=h,n=len(g),side=side,net_mean=net.mean(),t=t,half1=side*a.mean() if len(a) else np.nan,half2=side*b.mean() if len(b) else np.nan))
        R=pd.DataFrame(rows); N=len(R)
        surv=R[(R.t>=3.0)&(R.half1>0)&(R.half2>0)&(R.n>=60)]
        print(f"\n== {tk} {label}: cells {N} | t>=3 & both halves agree: {len(surv)} | chance at t>=3 one-sided: {N*(1-pn(3.0)):.1f}")
        if len(surv): print(surv.sort_values('t',ascending=False).head(12).round(2).to_string(index=False))
        return R,surv
    R,surv=scan(sess,'REAL')
    ctrl=sess.copy(); rng=np.random.default_rng(7)
    for h in (1,2,4): ctrl[f'fwd{h}']=ctrl[f'fwd{h}'].values*rng.choice([-1,1],len(ctrl))
    scan(ctrl,'CONTROL (sign-shuffled)')
    R['label']='REAL'; allrows.append(R)
A=pd.concat(allrows)
import psycopg2,psycopg2.extras,sys; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("CREATE TABLE IF NOT EXISTS v4_state_scan (run_date DATE, tk TEXT, hr INT, pos INT, rng INT, dow INT, vreg INT, hold INT, n INT, side INT, net_mean NUMERIC, t NUMERIC, half1 NUMERIC, half2 NUMERIC)")
cur.execute("DELETE FROM v4_state_scan WHERE run_date=current_date")
psycopg2.extras.execute_values(cur,"INSERT INTO v4_state_scan VALUES %s",[(dt.date.today(),r.tk,int(r.hr),int(r.pos),int(r.rng),int(r.dow),int(r.vreg),int(r.hold),int(r.n),int(r.side),float(round(r.net_mean,4)),float(round(r.t,3)),None if pd.isna(r.half1) else float(round(r.half1,4)),None if pd.isna(r.half2) else float(round(r.half2,4))) for r in A.itertuples()],page_size=2000)
print("\nstored v4_state_scan",len(A),"rows. RULE: a cell counts only if the REAL survivor count clearly exceeds the CONTROL survivor count.")
PYFILE
python3 -m py_compile state_scan.py && timeout 1500 python3 state_scan.py 2>&1 | grep -v Warning
