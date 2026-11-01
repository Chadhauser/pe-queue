#!/bin/bash
# 500: FINANCIAL — test the "Mallik" YouTube claim (Nov 2026): software engineer, fully systematic, 7 trend/MR rules long+short on
# TQQQ/SQQQ only, 1-2 trades/week, claims 40% CAGR / 33% max DD / +169% Aug 2022-Aug 2025, signals sold on Collective2.
# We code the published rule FAMILIES (moving-average, breakout, time-series momentum, RSI/z-score mean reversion; long/cash and
# long/short) with signal on QQQ, traded via TQQQ (long) / SQQQ (short), 0.05%/side, IS 2010-18 / OOS 2019-, and compare EVERY
# row to TQQQ and QQQ buy-and-hold over the same windows. Synthetic random-walk control first (must show no survivors).
# Table v4_tqqq. Explained to Peter before pushing (1 Nov 15:20).
mkdir -p /root/pe-fin && cd /root/pe-fin
cat > tqqq_test.py <<'PYFILE'
# 500: Mallik-style TQQQ/SQQQ systematic test. Signal on QQQ daily bars, traded as TQQQ (long) / SQQQ (short) / cash.
# Published claim (YouTube, Nov 2026): 7 strategies trend+MR long/short, 1-2 trades/week, 40% CAGR, 33% max DD, +169% Aug22-Aug25.
# Benchmarks: TQQQ buy&hold and QQQ buy&hold over the same windows. Costs 0.05%/side. IS 2010-2018, OOS 2019-today. Random-walk control.
import sys, math, warnings, numpy as np, pandas as pd
warnings.filterwarnings('ignore'); pd.set_option('display.width',220)
SYNTH='--synthetic' in sys.argv; COST=0.0005
import yfinance as yf
def dl(t):
    df=yf.download(t,start='2010-02-11',progress=False,auto_adjust=True,threads=False)
    if isinstance(df.columns,pd.MultiIndex): df.columns=df.columns.get_level_values(0)
    return df['Close'].dropna()
if '--fake' in sys.argv:
    rng0=np.random.default_rng(1); ix=pd.bdate_range('2010-02-11','2026-10-31'); r0=rng0.normal(0.0005,0.012,len(ix))
    q=pd.Series(100*np.exp(np.cumsum(r0)),index=ix); tq=pd.Series(100*np.exp(np.cumsum(3*r0)),index=ix); sq=pd.Series(100*np.exp(np.cumsum(-3*r0)),index=ix)
else: q,tq,sq=dl('QQQ'),dl('TQQQ'),dl('SQQQ')
idx=q.index.intersection(tq.index).intersection(sq.index); q,tq,sq=q[idx],tq[idx],sq[idx]
if SYNTH:
    rng=np.random.default_rng(7); r=np.log(q).diff().dropna(); s=rng.normal(0,r.std(),len(q)); q=pd.Series(100*np.exp(np.cumsum(s)),index=q.index)
    tq=pd.Series(100*np.exp(np.cumsum(3*s)),index=q.index); sq=pd.Series(100*np.exp(np.cumsum(-3*s)),index=q.index)
rq,rt,rs=q.pct_change().fillna(0),tq.pct_change().fillna(0),sq.pct_change().fillna(0)
print(f"bars {len(q)} | {q.index[0].date()} -> {q.index[-1].date()} | {'SYNTHETIC' if SYNTH else 'real'}")
def sma(n): return q.rolling(n).mean()
def rsi(n):
    d=q.diff(); up=d.clip(lower=0).ewm(alpha=1/n).mean(); dn=(-d.clip(upper=0)).ewm(alpha=1/n).mean(); return 100-100/(1+up/dn)
S={}
for n in (50,100,150,200): S[f'sma{n}_LC']=np.where(q>sma(n),1,0); S[f'sma{n}_LS']=np.where(q>sma(n),1,-1)
for f,s in ((10,50),(20,100),(50,200)): S[f'cross{f}_{s}_LC']=np.where(sma(f)>sma(s),1,0); S[f'cross{f}_{s}_LS']=np.where(sma(f)>sma(s),1,-1)
for n in (20,55,100): hi,lo=q.rolling(n).max().shift(1),q.rolling(n).min().shift(1); S[f'don{n}_LS']=pd.Series(np.where(q>hi,1,np.where(q<lo,-1,np.nan)),index=q.index).ffill().fillna(0).values
for m in (3,6,12): S[f'tsmom{m}_LC']=np.where(q>q.shift(21*m),1,0); S[f'tsmom{m}_LS']=np.where(q>q.shift(21*m),1,-1)
for n,lo,hi in ((2,10,90),(2,5,95),(3,15,85),(5,20,80)):
    r_=rsi(n); S[f'rsi{n}_{lo}_{hi}_MR']=pd.Series(np.where(r_<lo,1,np.where(r_>hi,-1,np.nan)),index=q.index).ffill().fillna(0).values
    S[f'rsi{n}_{lo}_MRtrend']=np.where((r_<lo)&(q>sma(200)),1,0)   # Connors-style: MR long only above 200d
for n in (10,20): z=(q-sma(n))/q.rolling(n).std(); S[f'z{n}_MR']=np.where(z<-2,1,np.where(z>2,-1,0))
def pnl(sig):
    pos=pd.Series(sig,index=q.index).shift(1).fillna(0)
    ret=np.where(pos>0,rt,np.where(pos<0,rs,0.0)); turn=pos.diff().abs().fillna(0)
    return pd.Series(ret,index=q.index)-COST*turn
def stats(p):
    p=p.dropna()
    if len(p)<250 or p.std()==0: return dict(cagr=0,sharpe=0,t=0,maxdd=0,n=len(p))
    eq=(1+p).cumprod(); yrs=len(p)/252; dd=((eq/eq.cummax())-1).min()
    return dict(cagr=round(eq.iloc[-1]**(1/yrs)-1,3),sharpe=round(p.mean()/p.std()*math.sqrt(252),2),t=round(p.mean()/(p.std()/math.sqrt(len(p))),2),maxdd=round(dd,3),n=len(p))
OOS='2019-01-01'; rows=[]
for k,sig in S.items():
    p=pnl(sig); a,i,o=stats(p),stats(p[p.index<OOS]),stats(p[p.index>=OOS]); w=p['2022-08-01':'2025-08-01']
    rows.append(dict(strategy=k,trades_per_wk=round(pd.Series(sig,index=q.index).diff().abs().gt(0).sum()/(len(q)/5),2),**{'all_'+x:a[x] for x in ('cagr','sharpe','maxdd')},is_sharpe=i['sharpe'],oos_sharpe=o['sharpe'],oos_t=o['t'],oos_maxdd=o['maxdd'],aug22_25=round((1+w).prod()-1,3) if len(w) else None))
T=pd.DataFrame(rows).sort_values('oos_t',ascending=False)
print("\n=== rule-based TQQQ/SQQQ (signal on QQQ), costs 0.05%/side ==="); print(T.to_string(index=False))
for lbl,r in (('TQQQ buy&hold',rt),('QQQ buy&hold',rq)):
    a,o=stats(r),stats(r[r.index>=OOS]); w=r['2022-08-01':'2025-08-01']; print(f"BENCH {lbl}: ALL cagr {a['cagr']} sharpe {a['sharpe']} maxdd {a['maxdd']} | OOS sharpe {o['sharpe']} maxdd {o['maxdd']} | Aug22-Aug25 {round((1+w).prod()-1,3)}")
n=len(T); thr=3.0; surv=T[(T.oos_t>=thr)&(T.is_sharpe>0)]
print(f"\ncells {n} | survivors oos_t>={thr} & IS>0: {len(surv)} | chance ~{n*0.0013:.2f}")
print("CLAIM CHECK: Mallik 40% CAGR / 33% maxDD / +169% Aug22-25 / 1-2 trades per week. Any row above that beats TQQQ buy&hold on Sharpe AND drawdown in OOS is worth a second look; a row that only matches buy&hold is leverage, not skill.")
if not SYNTH and '--fake' not in sys.argv:
    import psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
    con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
    cur.execute("CREATE TABLE IF NOT EXISTS v4_tqqq (run_date DATE, strategy TEXT, trades_per_wk NUMERIC, all_cagr NUMERIC, all_sharpe NUMERIC, all_maxdd NUMERIC, is_sharpe NUMERIC, oos_sharpe NUMERIC, oos_t NUMERIC, oos_maxdd NUMERIC, aug22_25 NUMERIC)")
    cur.execute("DELETE FROM v4_tqqq WHERE run_date=current_date")
    for r in T.itertuples(index=False): cur.execute("INSERT INTO v4_tqqq VALUES (current_date,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)",tuple(float(x) if isinstance(x,(np.floating,float)) and x is not None else x for x in r))
    print("stored v4_tqqq",n)
PYFILE
python3 -m py_compile tqqq_test.py || exit 1
echo "== synthetic control (random walk, must be ~0 survivors)"; timeout 600 python3 tqqq_test.py --synthetic 2>&1 | grep -v Warning | tail -6
echo; echo "== real"; timeout 900 python3 tqqq_test.py 2>&1 | grep -v Warning
