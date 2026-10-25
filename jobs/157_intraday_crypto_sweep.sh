#!/bin/bash
# 157: FACTORY v4 — INTRADAY FAMILY on free 1-minute data (Binance public klines, no key: BTC/ETH/SOL vs USDT, last 2 years).
# The daily sweep (151) was the engine shakedown; the prop-firm rule we want to copy (JJ Simon: mean reversion to the session open)
# is intraday. Crypto is the only market with free deep minute history, so it is the test bed; the same code runs on index futures
# once an intraday source is in place. Families (position per 5-min bar, acted next bar, no look-ahead):
#   OPEN-FADE: session open 00:00 UTC; after H hours, if price is > k*ATR(14d) above/below the open, fade it; exit at the open price,
#              at a stop of 2k*ATR, or at session end.   ORB: opening-range (first R minutes) breakout, exit at session end or stop.
#   LAST-HOUR MOMENTUM: hold the direction of the first 23 hours for the last hour.   VWAP-REVERT: fade > z sigma from session VWAP.
# Costs: 0.10% per side (Binance taker, which is what a market order pays) -> 0.20% a round trip, charged on every position change.
# IS = first half of the data, OOS = second half; t-stat; threshold scaled to the cell count; bootstrap on the top 10. -> v4_intraday.
mkdir -p /root/pe-factory/v4 && cd /root/pe-factory/v4 && cat > intraday_sweep.py <<'PYFILE'
import sys, math, time, datetime, itertools, warnings, requests, numpy as np, pandas as pd
warnings.filterwarnings('ignore'); pd.set_option('display.width',250); pd.set_option('display.max_rows',300)
SYNTH='--synthetic' in sys.argv; SYMS=['BTCUSDT','ETHUSDT','SOLUSDT']; COST=0.001; DAYS=730
def fetch(sym):
    url="https://api.binance.com/api/v3/klines"; end=int(time.time()*1000); start=end-DAYS*86400*1000; out=[]
    while start<end:
        r=requests.get(url,params={'symbol':sym,'interval':'5m','startTime':start,'limit':1000},timeout=20)
        if r.status_code!=200: print(sym,"http",r.status_code,r.text[:100]); time.sleep(5); continue
        k=r.json()
        if not k: break
        out+=k; start=k[-1][0]+1; time.sleep(0.15)
    df=pd.DataFrame(out,columns=['t','o','h','l','c','v','ct','qv','n','tb','tq','x'])[['t','o','h','l','c','v']].astype(float)
    df['t']=pd.to_datetime(df.t,unit='ms',utc=True); return df.set_index('t')
def synth(sym):
    rng=np.random.default_rng(sum(map(ord,sym))); idx=pd.date_range('2024-10-01',periods=DAYS*288,freq='5min',tz='UTC')
    r=rng.normal(0,0.0015,len(idx)); c=100*np.exp(np.cumsum(r)); df=pd.DataFrame({'c':c},index=idx); df['o']=df.c.shift(1).fillna(df.c)
    df['h']=np.maximum(df.o,df.c)*(1+abs(rng.normal(0,0.0005,len(idx)))); df['l']=np.minimum(df.o,df.c)*(1-abs(rng.normal(0,0.0005,len(idx)))); df['v']=1.0; return df
def prep(df):
    df=df.copy(); df['day']=df.index.floor('D'); df['mins']=(df.index-df.day).dt.total_seconds()/60
    daily=df.groupby('day').agg(o=('o','first'),h=('h','max'),l=('l','min'),c=('c','last'))
    tr=pd.concat([daily.h-daily.l,(daily.h-daily.c.shift()).abs(),(daily.l-daily.c.shift()).abs()],axis=1).max(axis=1); daily['atr']=tr.rolling(14).mean().shift(1)   # yesterday's ATR: no look-ahead
    df=df.join(daily[['o','atr']].rename(columns={'o':'dopen'}),on='day')
    df['vwap']=(df.c*df.v).groupby(df.day).cumsum()/df.v.groupby(df.day).cumsum().replace(0,np.nan)
    return df
# ---- families: return position series in {-1,0,1}
def open_fade(df,p):
    pos=pd.Series(0.0,index=df.index); dev=(df.c-df.dopen)/df.atr; armed=(df.mins>=p['H']*60)&(df.mins<1430)
    state=0; dopen=None; out=np.zeros(len(df)); c=df.c.values; d=dev.values; a=armed.values; dayv=df.day.values; do=df.dopen.values; atr=df.atr.values; prev_day=None
    for i in range(len(df)):
        if dayv[i]!=prev_day: state=0; prev_day=dayv[i]
        if state==0:
            if a[i] and not np.isnan(d[i]):
                if d[i]>=p['k']: state=-1
                elif d[i]<=-p['k']: state=1
        else:
            # exit: back at the open, stop at 2k ATR beyond entry side, or session end
            if (state==1 and (c[i]>=do[i] or c[i]<=do[i]-2*p['k']*atr[i])) or (state==-1 and (c[i]<=do[i] or c[i]>=do[i]+2*p['k']*atr[i])): state=0
        out[i]=state
    return pd.Series(out,index=df.index)
def orb(df,p):
    hi=df.h.where(df.mins<p['R']).groupby(df.day).transform('max'); lo=df.l.where(df.mins<p['R']).groupby(df.day).transform('min')
    pos=pd.Series(np.nan,index=df.index); after=df.mins>=p['R']
    pos[after&(df.c>hi)]=1; pos[after&(df.c<lo)]=-1; pos[~after]=0
    pos=pos.groupby(df.day).ffill().fillna(0)
    # stop: back inside the range midpoint
    mid=(hi+lo)/2; pos[(pos==1)&(df.c<mid)]=0; pos[(pos==-1)&(df.c>mid)]=0
    return pos.groupby(df.day).ffill().fillna(0)
def last_hour_mom(df,p):
    pos=pd.Series(0.0,index=df.index); late=df.mins>=1440-p['M']; dirn=np.sign(df.c-df.dopen); pos[late]=dirn[late]; return pos
def vwap_revert(df,p):
    dev=(df.c-df.vwap)/df.c; sd=dev.groupby(df.day).transform(lambda s: s.expanding().std()); z=dev/sd
    pos=pd.Series(np.nan,index=df.index); pos[z>p['z']]=-1; pos[z<-p['z']]=1; pos[z.abs()<0.3]=0; pos[df.mins<60]=0
    return pos.groupby(df.day).ffill().fillna(0)
def build_configs():
    C=[]
    for H,k in itertools.product((1,2,4,6),(0.5,1.0,1.5)): C.append((f'openfade_H{H}_k{k}',open_fade,{'H':H,'k':k},'meanrev'))
    for R in (15,30,60,120): C.append((f'orb_{R}',orb,{'R':R},'breakout'))
    for M in (60,120,240): C.append((f'lasthour_{M}',last_hour_mom,{'M':M},'momentum'))
    for z in (1.5,2.0,3.0): C.append((f'vwaprev_{z}',vwap_revert,{'z':z},'meanrev'))
    return C
def backtest(df,pos):
    ret=df.c.pct_change().fillna(0); pos=pos.clip(-1,1).shift(1).fillna(0); turn=pos.diff().abs().fillna(0); return pos*ret-COST*turn, turn
def stats(pnl,bars_per_year=288*365):
    if len(pnl)<1000 or pnl.std()==0: return None
    sh=pnl.mean()/pnl.std()*math.sqrt(bars_per_year); t=pnl.mean()/(pnl.std()/math.sqrt(len(pnl))); eq=(1+pnl).cumprod(); dd=((eq/eq.cummax())-1).min()
    return dict(sharpe=sh,t=t,ret=eq.iloc[-1]-1,maxdd=dd)
def main():
    data={s:(synth(s) if SYNTH else fetch(s)) for s in SYMS}
    for s,df in data.items(): print(s,"bars",len(df),df.index.min(),"->",df.index.max(),flush=True)
    cfgs=build_configs(); rows=[]; oos_ret={}
    for s,raw in data.items():
        df=prep(raw); split=df.index[len(df)//2]
        for name,fn,params,fam in cfgs:
            pos=fn(df,params); pnl,turn=backtest(df,pos); ins=pnl[pnl.index<split]; oos=pnl[pnl.index>=split]; si=stats(ins); so=stats(oos)
            if not si or not so: continue
            rows.append(dict(config=name,family=fam,sym=s,is_sharpe=si['sharpe'],oos_sharpe=so['sharpe'],oos_t=so['t'],oos_ret=so['ret'],oos_maxdd=so['maxdd'],trades_oos=int((turn[turn.index>=split]>0).sum()),bh_oos=float(df.c[df.index>=split].iloc[-1]/df.c[df.index>=split].iloc[0]-1)))
            oos_ret[(name,s)]=oos
    R=pd.DataFrame(rows); N=len(R)
    print(f"\n=== INTRADAY SWEEP: {N} backtests | 5-min bars | cost {COST*100:.2f}% per side | IS first half / OOS second half ===")
    from math import erf,sqrt
    def pnorm(x): return 0.5*(1+erf(x/sqrt(2)))
    for thr in (2.0,3.0,3.5): print(f"  OOS t>={thr} & IS positive: {int(((R.oos_t>=thr)&(R.is_sharpe>0)).sum())} of {N} | chance: {N*(1-pnorm(thr)):.1f}")
    print("\nAll cells by OOS t:\n",R.sort_values('oos_t',ascending=False).round(3).to_string(index=False))
    print("\nFamily sensitivity (mean / sd / % positive OOS Sharpe):\n",R.groupby('family').agg(n=('oos_sharpe','size'),mean=('oos_sharpe','mean'),sd=('oos_sharpe','std'),pct_pos=('oos_sharpe',lambda s:(s>0).mean())).round(3).to_string())
    rng=np.random.default_rng(5); boot=[]
    for r in R.sort_values('oos_t',ascending=False).head(10).itertuples():
        x=oos_ret[(r.config,r.sym)].values; shs=[]
        for _ in range(300):
            b=rng.choice(x,len(x),replace=True); shs.append(b.mean()/b.std()*math.sqrt(288*365) if b.std()>0 else 0)
        boot.append(dict(config=r.config,sym=r.sym,oos_sharpe=round(r.oos_sharpe,2),p5=round(np.percentile(shs,5),2),p95=round(np.percentile(shs,95),2),flag='SOLID' if np.percentile(shs,5)>0.3 else 'FRAGILE'))
    print("\nBootstrap top 10:\n",pd.DataFrame(boot).to_string(index=False))
    print("\nNOTE: bh_oos = buy-and-hold return over the same OOS window — a long-biased config must beat it to mean anything.")
    if not SYNTH:
        import psycopg2, psycopg2.extras; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
        con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
        cur.execute("CREATE TABLE IF NOT EXISTS v4_intraday (run_date DATE, config TEXT, family TEXT, sym TEXT, is_sharpe NUMERIC, oos_sharpe NUMERIC, oos_t NUMERIC, oos_ret NUMERIC, oos_maxdd NUMERIC, trades_oos INT, bh_oos NUMERIC)")
        cur.execute("DELETE FROM v4_intraday WHERE run_date=current_date")
        psycopg2.extras.execute_values(cur,"INSERT INTO v4_intraday VALUES %s",[(datetime.date.today(),r.config,r.family,r.sym,*(float(round(v,4)) for v in (r.is_sharpe,r.oos_sharpe,r.oos_t,r.oos_ret,r.oos_maxdd)),int(r.trades_oos),float(round(r.bh_oos,4))) for r in R.itertuples()])
        print("stored",N)
main()
PYFILE
python3 -m py_compile intraday_sweep.py || exit 1
echo "== synthetic leak test"; timeout 900 python3 intraday_sweep.py --synthetic 2>&1 | sed -n 1,10p
echo "== real run"; timeout 3000 python3 intraday_sweep.py 2>&1 | grep -v Warning
