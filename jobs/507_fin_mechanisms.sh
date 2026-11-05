#!/bin/bash
# 507: FINANCIAL — five pre-registered mechanism tests (ours, directions fixed 4 Nov before running): lev-ETF rebalance, BTC overnight
# lead, TLT first-hour lead, month-end last hour, Friday strike pin. Each: n, mean bps, t, IS/OOS, sign-shuffled control. Tested offline.
cd /root/pe-fin
cat > mechanisms.py <<'PYFILE'
# 507: FIVE PRE-REGISTERED MECHANISM TESTS (our own, stated in advance 4 Nov 2026, direction fixed before running). One test each,
# 2 bps round-trip cost, IS/OOS halves, sign-shuffled control. Data: Alpaca 1-min (QQQ, TQQQ, TLT), Alpaca daily BTC/USD.
#  H1 leveraged-ETF rebalance: on days where QQQ is up/down >=1% by 15:30, the 15:30->close move continues in the same direction.
#  H2 crypto overnight lead: BTC's move from 16:00 ET prev close to 09:30 ET predicts QQQ open->close direction (same sign).
#  H3 bond first-hour lead: TLT's 09:30->10:30 move predicts QQQ's 10:30->12:30 move with the OPPOSITE sign (risk-on/off).
#  H4 month-end flow: last trading day of month, 15:00->close QQQ move is positive (pension/rebalance buying).
#  H5 expiry pin: on Fridays, in the last hour QQQ moves toward the nearest $5 strike (|dist| shrinks from 15:00 to close).
import sys, os, math, datetime, numpy as np, pandas as pd, requests
sys.path.insert(0,'/root/pe-fin'); from alpaca_load import load
sys.path.insert(0,'/root/pe-queue/runner'); import creds
NMIN=390; COST=0.0002; rng=np.random.default_rng(21)
def mat(sym):
    b=load(sym); ny=b.index.tz_convert('America/New_York'); mi=(ny.hour*60+ny.minute)-570; ok=(mi>=0)&(mi<NMIN)
    df=pd.DataFrame({'d':ny[ok].date,'m':mi[ok],'c':b.close.values[ok]})
    P=df.pivot_table(index='d',columns='m',values='c',aggfunc='last').reindex(columns=range(NMIN)); P=P[P.notna().sum(axis=1)>=200].ffill(axis=1).bfill(axis=1)
    return P
def report(name,x,hyp_dir):
    x=np.asarray(x,float); x=x[np.isfinite(x)]; n=len(x); h=n//2
    if n<30: print(f"{name}: n {n} too few"); return
    t=lambda a:a.mean()/(a.std(ddof=1)/math.sqrt(len(a))) if len(a)>5 and a.std()>0 else 0
    ctrl=x*rng.choice([-1,1],n)
    print(f"{name}: n {n} | mean {1e4*x.mean():+.1f} bps | t {t(x):.2f} | IS {1e4*x[:h].mean():+.1f} bps t {t(x[:h]):.2f} | OOS {1e4*x[h:].mean():+.1f} bps t {t(x[h:]):.2f} | control t {t(ctrl):.2f} | pre-registered sign {hyp_dir} -> {'SUPPORTED' if (t(x)>=2.5 and x[:h].mean()>0 and x[h:].mean()>0) else 'NOT YET'}")
Q=mat('QQQ'); print("QQQ days",len(Q))
# H1
up=Q[360]/Q[0]-1; last=Q[389]/Q[360]-1; sel=up.abs()>=0.01; H1=np.sign(up[sel])*last[sel]-COST; report("H1 lev-ETF rebalance (|move by 15:30|>=1%, trade with it to close)",H1,"+")
# H2 BTC overnight -> QQQ open-close
E=creds.all_vars(); H={'APCA-API-KEY-ID':E.get('ALPACA_KEY'),'APCA-API-SECRET-KEY':E.get('ALPACA_SECRET')}
r=requests.get('https://data.alpaca.markets/v1beta3/crypto/us/bars',params={'symbols':'BTC/USD','timeframe':'1Hour','start':'2020-07-01T00:00:00Z','end':f'{datetime.date.today()}T00:00:00Z','limit':10000},headers=H,timeout=60)
frames=[]; tok=None
while True:
    p={'symbols':'BTC/USD','timeframe':'1Hour','start':'2020-07-01T00:00:00Z','end':f'{datetime.date.today()}T00:00:00Z','limit':10000}
    if tok: p['page_token']=tok
    j=requests.get('https://data.alpaca.markets/v1beta3/crypto/us/bars',params=p,headers=H,timeout=60).json(); bars=(j.get('bars') or {}).get('BTC/USD') or []
    if bars: frames.append(pd.DataFrame(bars))
    tok=j.get('next_page_token')
    if not tok: break
B=pd.concat(frames); B['ts']=pd.to_datetime(B['t'],utc=True).dt.tz_convert('America/New_York'); B=B.set_index('ts').sort_index()
print("BTC hourly bars",len(B))
bt=B['c']; qd=pd.to_datetime(Q.index)
prev16=[]; at930=[]
for d in qd:
    a=bt[:pd.Timestamp(d-pd.Timedelta(days=1)).tz_localize('America/New_York').replace(hour=16)]; b_=bt[:pd.Timestamp(d).tz_localize('America/New_York').replace(hour=9,minute=30)]
    prev16.append(a.iloc[-1] if len(a) else np.nan); at930.append(b_.iloc[-1] if len(b_) else np.nan)
btmove=pd.Series(np.array(at930)/np.array(prev16)-1,index=Q.index); qoc=Q[389]/Q[0]-1
sel=btmove.abs()>=0.01; H2=np.sign(btmove[sel])*qoc[sel]-COST; report("H2 BTC overnight >=1% -> QQQ open->close same sign",H2,"+")
# H3 TLT first hour -> QQQ 10:30-12:30 opposite sign
T=mat('TLT'); idx=Q.index.intersection(T.index); tl=T.loc[idx,60]/T.loc[idx,0]-1; q2=Q.loc[idx,180]/Q.loc[idx,60]-1
sel=tl.abs()>=0.003; H3=-np.sign(tl[sel])*q2[sel]-COST; report("H3 TLT first-hour >=0.3% -> QQQ 10:30-12:30 OPPOSITE sign",H3,"+")
# H4 month-end last hour long
qd=pd.Series(pd.to_datetime(Q.index),index=Q.index); me=qd.dt.month!=qd.shift(-1).dt.month; H4=(Q[389]/Q[330]-1)[me]-COST; report("H4 last trading day of month, long 15:00->close",H4,"+")
# H5 expiry pin on Fridays: distance to nearest $5 strike shrinks 15:00 -> close (trade toward strike)
fri=qd.dt.dayofweek==4; p15=Q.loc[fri,330]; strike=(p15/5).round()*5; direction=np.sign(strike-p15); move=Q.loc[fri,389]/p15-1
sel=(strike-p15).abs()/p15>0.001; H5=direction[sel]*move[sel]-COST; report("H5 Friday last hour, trade toward nearest $5 strike (dist>0.1%)",H5,"+")
print("\nOWNER RULE: each NOT YET gets its next door in the header; SUPPORTED goes to the portfolio MC with ORB.")
PYFILE
python3 -m py_compile mechanisms.py || exit 1
timeout 1500 python3 mechanisms.py 2>&1 | grep -v Warning
