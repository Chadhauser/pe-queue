#!/bin/bash
# 151: FACTORY v4 — FINANCIAL SWEEP (the AI Pathways four layers, run honestly). Free daily bars via yfinance, 2010 -> today.
# UNIVERSE (~60): FX majors/crosses, index/bond/commodity futures proxies, crypto, mega-cap equities and sector ETFs.
# LAYER 1: strategy library as functions f(df,params) -> position {-1,0,1}, signals shifted one bar (no look-ahead), tagged by
#   family (trend / meanrev / volatility); build_configs() = ~100 configs x ~60 assets = ~6,000 backtests.
# LAYER 2: engine with per-asset-class round-turn costs (FX 0.03%, futures 0.03%, equities/ETF 0.05%, crypto 0.15%) charged on every
#   position change; in-sample 2010-2018 / out-of-sample 2019-today; OOS t-stat; survivor threshold scaled to the test count
#   (6,000 tests -> t >= 3.5 OOS, also reported at 2.0 and 3.0 so you can see the funnel); % of OOS years positive.
# LAYER 3: parameter sensitivity per family x asset class (mean, sd, % positive OOS Sharpe) and bootstrap (500 resamples of OOS daily
#   returns) on the top 20: p5/p50/p95 Sharpe, worst drawdown, SOLID/FRAGILE.
# LAYER 4: cross-sectional momentum across the whole universe (rank every 21 days, long top third / short bottom third, 3/6/12-1 month
#   lookbacks, costs on turnover) vs the best single-asset momentum.
# Caveat printed with the results: tickers alive today = survivorship in the equity set; daily bars; no slippage beyond the cost table.
# Tested locally on synthetic random walks first (expect ~0 survivors at t>=3.5 — if random data passes, the engine leaks).
mkdir -p /root/pe-factory/v4 && cd /root/pe-factory/v4
pip install -q yfinance --break-system-packages 2>&1 | tail -1
cat > fin_sweep.py <<'PYFILE'
import sys, math, datetime, itertools, warnings, numpy as np, pandas as pd
warnings.filterwarnings('ignore')
SYNTH = '--synthetic' in sys.argv
pd.set_option('display.width',250); pd.set_option('display.max_rows',300)
# ---------- universe ----------
UNI={'fx':['EURUSD=X','GBPUSD=X','USDJPY=X','AUDUSD=X','USDCAD=X','USDCHF=X','NZDUSD=X','EURGBP=X','EURJPY=X','GBPJPY=X'],
     'futures':['ES=F','NQ=F','YM=F','RTY=F','GC=F','SI=F','CL=F','NG=F','HG=F','ZB=F','ZN=F','^FTSE','^GDAXI','^N225'],
     'crypto':['BTC-USD','ETH-USD','SOL-USD'],
     'equity':['SPY','QQQ','IWM','DIA','TLT','GLD','USO','XLF','XLE','XLK','XLV','XLU','XLI','XLP','XLY','EEM','EFA','AAPL','MSFT','AMZN','GOOGL','META','NVDA','TSLA','JPM','XOM','JNJ','BRK-B']}
COST={'fx':0.0003,'futures':0.0003,'crypto':0.0015,'equity':0.0005}   # round-turn fraction, charged per unit of |position change|
START='2010-01-01'; OOS_FROM='2019-01-01'; MIN_BARS=500
def load():
    data={}
    if SYNTH:
        rng=np.random.default_rng(7); idx=pd.bdate_range('2010-01-01','2026-10-01')
        for cls,ts in UNI.items():
            for t in ts:
                r=rng.normal(0.0002,0.012,len(idx)); px=100*np.exp(np.cumsum(r))
                df=pd.DataFrame({'Close':px},index=idx); df['High']=df.Close*(1+abs(rng.normal(0,0.006,len(idx)))); df['Low']=df.Close*(1-abs(rng.normal(0,0.006,len(idx)))); df['Volume']=1e6
                data[(cls,t)]=df
        return data
    import yfinance as yf
    for cls,ts in UNI.items():
        for t in ts:
            try:
                df=yf.download(t,start=START,progress=False,auto_adjust=True,threads=False)
                if isinstance(df.columns,pd.MultiIndex): df.columns=df.columns.get_level_values(0)
                df=df.dropna(subset=['Close'])
                if len(df)>=MIN_BARS: data[(cls,t)]=df[['Close','High','Low','Volume']].copy()
                else: print("skip (bars)",t,len(df))
            except Exception as e: print("skip",t,repr(e)[:80])
    return data
# ---------- layer 1: strategy library (position in {-1,0,1}; NOT shifted here — engine shifts) ----------
def sma_cross(df,p):
    c=df.Close; f=c.rolling(p['fast']).mean(); s=c.rolling(p['slow']).mean(); return np.sign(f-s)
def tsmom(df,p):
    c=df.Close; return np.sign(c/c.shift(p['lb'])-1)
def donchian(df,p):
    c=df.Close; hi=c.rolling(p['n']).max().shift(1); lo=c.rolling(p['n']).min().shift(1)
    pos=pd.Series(np.nan,index=c.index); pos[c>hi]=1; pos[c<lo]=-1; return pos.ffill().fillna(0)
def boll_breakout(df,p):
    c=df.Close; m=c.rolling(p['n']).mean(); sd=c.rolling(p['n']).std()
    pos=pd.Series(np.nan,index=c.index); pos[c>m+p['k']*sd]=1; pos[c<m-p['k']*sd]=-1; pos[(c<m)&(pos.ffill()==1)]=0; pos[(c>m)&(pos.ffill()==-1)]=0; return pos.ffill().fillna(0)
def macd(df,p):
    c=df.Close; line=c.ewm(span=p['f']).mean()-c.ewm(span=p['s']).mean(); sig=line.ewm(span=p['sig']).mean(); return np.sign(line-sig)
def rsi_mr(df,p):
    c=df.Close; d=c.diff(); up=d.clip(lower=0).ewm(alpha=1/p['n']).mean(); dn=(-d.clip(upper=0)).ewm(alpha=1/p['n']).mean(); rsi=100-100/(1+up/dn)
    pos=pd.Series(np.nan,index=c.index); pos[rsi<p['lo']]=1; pos[rsi>p['hi']]=-1; pos[(rsi>50)&(pos.ffill()==1)]=0; pos[(rsi<50)&(pos.ffill()==-1)]=0; return pos.ffill().fillna(0)
def zscore_mr(df,p):
    c=df.Close; z=(c-c.rolling(p['n']).mean())/c.rolling(p['n']).std()
    pos=pd.Series(np.nan,index=c.index); pos[z<-p['z']]=1; pos[z>p['z']]=-1; pos[(z.abs()<0.25)]=0; return pos.ffill().fillna(0)
def boll_mr(df,p):
    c=df.Close; m=c.rolling(p['n']).mean(); sd=c.rolling(p['n']).std()
    pos=pd.Series(np.nan,index=c.index); pos[c<m-p['k']*sd]=1; pos[c>m+p['k']*sd]=-1; pos[((c>m)&(pos.ffill()==1))|((c<m)&(pos.ffill()==-1))]=0; return pos.ffill().fillna(0)
def atr_breakout(df,p):
    c=df.Close; tr=pd.concat([df.High-df.Low,(df.High-c.shift()).abs(),(df.Low-c.shift()).abs()],axis=1).max(axis=1); atr=tr.rolling(p['n']).mean()
    ref=c.shift(1).rolling(p['n']).mean(); pos=pd.Series(np.nan,index=c.index); pos[c>ref+p['k']*atr]=1; pos[c<ref-p['k']*atr]=-1; pos[(c-ref).abs()<0.5*atr]=0; return pos.ffill().fillna(0)
def build_configs():
    C=[]
    for f,s in itertools.product((5,10,20,50),(50,100,200)):
        if f<s: C.append((f'sma_{f}_{s}',sma_cross,{'fast':f,'slow':s},'trend'))
    for lb in (10,20,40,60,120,250): C.append((f'tsmom_{lb}',tsmom,{'lb':lb},'trend'))
    for n in (10,20,40,55,100): C.append((f'donch_{n}',donchian,{'n':n},'trend'))
    for n,k in itertools.product((20,50),(1.5,2.0,2.5)): C.append((f'bollbo_{n}_{k}',boll_breakout,{'n':n,'k':k},'trend'))
    for f,s,g in ((12,26,9),(8,21,5),(20,50,10)): C.append((f'macd_{f}_{s}_{g}',macd,{'f':f,'s':s,'sig':g},'trend'))
    for n,lo,hi in ((14,30,70),(14,25,75),(7,20,80),(2,10,90),(2,5,95)): C.append((f'rsi_{n}_{lo}_{hi}',rsi_mr,{'n':n,'lo':lo,'hi':hi},'meanrev'))
    for n,z in itertools.product((10,20,50),(1.5,2.0,2.5)): C.append((f'z_{n}_{z}',zscore_mr,{'n':n,'z':z},'meanrev'))
    for n,k in itertools.product((10,20,50),(1.5,2.0,2.5)): C.append((f'bollmr_{n}_{k}',boll_mr,{'n':n,'k':k},'meanrev'))
    for n,k in itertools.product((14,20,50),(1.0,1.5,2.0,3.0)): C.append((f'atr_{n}_{k}',atr_breakout,{'n':n,'k':k},'volatility'))
    return C
# ---------- layer 2: engine ----------
def backtest(df,pos,cost):
    ret=df.Close.pct_change().fillna(0); pos=pos.replace([np.inf,-np.inf],0).fillna(0).clip(-1,1).shift(1).fillna(0)   # act next bar
    turn=pos.diff().abs().fillna(0); pnl=pos*ret-cost*turn
    return pnl,turn
def stats(pnl):
    if len(pnl)<200 or pnl.std()==0: return None
    sh=pnl.mean()/pnl.std()*math.sqrt(252); t=pnl.mean()/(pnl.std()/math.sqrt(len(pnl))); eq=(1+pnl).cumprod(); dd=((eq/eq.cummax())-1).min()
    yrs=pnl.groupby(pnl.index.year).sum(); return dict(sharpe=sh,t=t,cagr=eq.iloc[-1]**(252/len(pnl))-1,maxdd=dd,years_pos=(yrs>0).mean(),n_years=len(yrs))
def main():
    data=load(); print("assets loaded:",len(data),"| synthetic" if SYNTH else "| yfinance",flush=True)
    cfgs=build_configs(); print("configs:",len(cfgs),"| backtests:",len(cfgs)*len(data),flush=True)
    rows=[]; oos_ret={}
    for (cls,tk),df in data.items():
        for name,fn,params,fam in cfgs:
            try: pos=fn(df,params)
            except Exception as e: print("err",name,tk,repr(e)[:60]); continue
            pnl,turn=backtest(df,pos,COST[cls]); ins=pnl[pnl.index<OOS_FROM]; oos=pnl[pnl.index>=OOS_FROM]
            si=stats(ins); so=stats(oos)
            if not si or not so: continue
            trades=int((turn[turn.index>=OOS_FROM]>0).sum())
            rows.append(dict(config=name,family=fam,asset=tk,cls=cls,is_sharpe=si['sharpe'],oos_sharpe=so['sharpe'],oos_t=so['t'],oos_cagr=so['cagr'],oos_maxdd=so['maxdd'],years_pos=so['years_pos'],trades_oos=trades))
            oos_ret[(name,tk)]=oos
    R=pd.DataFrame(rows); N=len(R); print(f"\n=== LAYER 2: {N} backtests scored | IS {START[:4]}-2018, OOS 2019-today | costs per class {COST} ===")
    for thr in (2.0,3.0,3.5):
        s=R[(R.oos_t>=thr)&(R.is_sharpe>0)]; print(f"  OOS t >= {thr} AND IS positive: {len(s)} of {N}")
    from math import erf, sqrt
    def pnorm(x): return 0.5*(1+erf(x/sqrt(2)))
    print("  expected by pure chance (one-sided):",{thr:round(N*(1-pnorm(thr)),1) for thr in (2.0,3.0,3.5)})
    top=R.sort_values('oos_t',ascending=False).head(25)
    print("\nTop 25 by OOS t (per asset):\n",top.round(3).to_string(index=False))
    print("\nBy asset class (mean OOS Sharpe, % configs positive OOS):\n",R.groupby('cls').agg(n=('oos_sharpe','size'),mean_oos=('oos_sharpe','mean'),pct_pos=('oos_sharpe',lambda s:(s>0).mean())).round(3).to_string())
    # ---------- layer 3: sensitivity + bootstrap ----------
    print("\n=== LAYER 3a: parameter sensitivity — family x class (mean / sd / % positive OOS Sharpe; tight+positive = real, one-setting wonders = curve fit) ===")
    print(R.groupby(['family','cls']).agg(n=('oos_sharpe','size'),mean=('oos_sharpe','mean'),sd=('oos_sharpe','std'),pct_pos=('oos_sharpe',lambda s:(s>0).mean())).round(3).to_string())
    print("\n=== LAYER 3b: bootstrap (500 resamples of OOS daily returns) on the top 20 ===")
    rng=np.random.default_rng(1); boot=[]
    for r in top.head(20).itertuples():
        x=oos_ret[(r.config,r.asset)].values; shs=[]; dds=[]
        for _ in range(500):
            s=rng.choice(x,size=len(x),replace=True); shs.append(s.mean()/s.std()*math.sqrt(252) if s.std()>0 else 0)
            eq=np.cumprod(1+rng.permutation(x)); dds.append(((eq/np.maximum.accumulate(eq))-1).min())
        p5,p50,p95=np.percentile(shs,[5,50,95]); boot.append(dict(config=r.config,asset=r.asset,oos_sharpe=round(r.oos_sharpe,2),p5=round(p5,2),p50=round(p50,2),p95=round(p95,2),worst_dd=round(min(dds),3),flag='SOLID' if p5>0.3 else 'FRAGILE'))
    B=pd.DataFrame(boot); print(B.to_string(index=False) if len(B) else "none")
    # ---------- layer 4: cross-sectional momentum ----------
    print("\n=== LAYER 4: cross-sectional momentum across the whole universe (rebalance every 21 bars, long top third / short bottom third) ===")
    closes=pd.DataFrame({tk:df.Close for (cls,tk),df in data.items()}).ffill(); cls_of={tk:cls for (cls,tk) in data}
    rets=closes.pct_change().fillna(0); out=[]
    for lb_name,lb,skip in (('3m',63,0),('6m',126,0),('12m-1',252,21)):
        mom=closes.shift(skip)/closes.shift(lb)-1; w=pd.DataFrame(0.0,index=closes.index,columns=closes.columns); last=None
        for i in range(lb+skip,len(closes),21):
            m=mom.iloc[i].dropna();
            if len(m)<9: continue
            k=max(1,len(m)//3); r=m.rank(); lo=m.index[r<=k]; hi=m.index[r>len(m)-k]
            row=pd.Series(0.0,index=closes.columns); row[hi]=1/k; row[lo]=-1/k; w.iloc[i:i+21]=row.values
        w=w.shift(1).fillna(0); turn=w.diff().abs().fillna(0)
        cost=pd.Series({tk:COST[cls_of[tk]] for tk in closes.columns})
        pnl=(w*rets).sum(axis=1)-(turn*cost).sum(axis=1); ins=pnl[pnl.index<OOS_FROM]; oos=pnl[pnl.index>=OOS_FROM]; si=stats(ins); so=stats(oos)
        out.append(dict(lookback=lb_name,is_sharpe=si['sharpe'] if si else None,oos_sharpe=so['sharpe'] if so else None,oos_t=so['t'] if so else None,oos_maxdd=so['maxdd'] if so else None,years_pos=so['years_pos'] if so else None))
    X=pd.DataFrame(out).round(3); print(X.to_string(index=False))
    best_single=R[R.config.str.startswith('tsmom')].sort_values('oos_sharpe',ascending=False).head(1)
    print("best single-asset tsmom OOS Sharpe for comparison:",best_single[['config','asset','oos_sharpe']].to_string(index=False) if len(best_single) else 'n/a')
    print("\nCAVEATS: equity tickers alive today (survivorship); daily bars; costs are a flat table with no slippage; no overnight funding on FX/crypto.")
    if not SYNTH:
        import psycopg2, psycopg2.extras; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
        con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
        cur.execute("CREATE TABLE IF NOT EXISTS v4_fin_results (run_date DATE, config TEXT, family TEXT, asset TEXT, cls TEXT, is_sharpe NUMERIC, oos_sharpe NUMERIC, oos_t NUMERIC, oos_cagr NUMERIC, oos_maxdd NUMERIC, years_pos NUMERIC, trades_oos INT)")
        cur.execute("DELETE FROM v4_fin_results WHERE run_date=current_date")
        psycopg2.extras.execute_values(cur,"INSERT INTO v4_fin_results VALUES %s",[(datetime.date.today(),r.config,r.family,r.asset,r.cls,*(float(round(v,4)) for v in (r.is_sharpe,r.oos_sharpe,r.oos_t,r.oos_cagr,r.oos_maxdd,r.years_pos)),int(r.trades_oos)) for r in R.itertuples()],page_size=2000)
        cur.execute("CREATE TABLE IF NOT EXISTS v4_fin_xsmom (run_date DATE, lookback TEXT, is_sharpe NUMERIC, oos_sharpe NUMERIC, oos_t NUMERIC, oos_maxdd NUMERIC, years_pos NUMERIC)")
        cur.execute("DELETE FROM v4_fin_xsmom WHERE run_date=current_date")
        psycopg2.extras.execute_values(cur,"INSERT INTO v4_fin_xsmom VALUES %s",[(datetime.date.today(),r.lookback,r.is_sharpe,r.oos_sharpe,r.oos_t,r.oos_maxdd,r.years_pos) for r in X.itertuples()])
        print("stored v4_fin_results",len(R),"rows")
main()
PYFILE
python3 -m py_compile fin_sweep.py || exit 1
echo "== synthetic leak test (random walks: expect survivors at t>=3.5 ≈ chance)"
timeout 1500 python3 fin_sweep.py --synthetic 2>&1 | sed -n 1,12p
echo "== real run"
timeout 3400 python3 fin_sweep.py 2>&1 | grep -v Warning
