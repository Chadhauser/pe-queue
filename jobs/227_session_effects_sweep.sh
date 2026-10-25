#!/bin/bash
# 227: FINANCIAL — new family group the daily sweep cannot express: INTRADAY SESSION EFFECTS on 1h bars (yfinance, ~2.4y).
# Families (position in {-1,0,1} set on bar t = held during bar t+1, engine shifts; cost charged per unit of |position change|):
#   open_cont  : sign of the first k bars of a session (asia 23 / london 07 / ny 13 UTC), hold h bars; continuation and fade
#   overlap    : London-NY overlap 13-16 UTC: sign of prior lb bars, hold h bars; continuation and fade
#   last_hour  : sign of the day-session return so far at 20:00 UTC, hold the last bar (20-21 UTC); continuation and fade
#   overnight  : long/short overnight only (21->13 UTC) and day only (13->21 UTC) — the overnight-premium test
#   weekday    : long/short one weekday
#   tom        : turn-of-month (last 2 + first 3 trading days) long/short
# 68 configs x 6 instruments = ~400 cells. IS = first half of each instrument's history, OOS = second half (only ~2.4y exist — scope stated).
# Costs: 0.03% per position change (brief's conservative table) as primary; survivors re-shown at 0.01%.
# Synthetic leak test first: random returns on the REAL bar index (same hours/gaps) must give ~0 at t>=3.0.
mkdir -p /root/pe-factory/v4 && cd /root/pe-factory/v4
cat > session_sweep.py <<'PYFILE'
import sys, math, datetime, warnings, numpy as np, pandas as pd
warnings.filterwarnings('ignore'); pd.set_option('display.width',250); pd.set_option('display.max_rows',200)
SYNTH='--synthetic' in sys.argv
UNI={'futures':['ES=F','NQ=F','GC=F','CL=F'],'fx':['EURUSD=X','GBPUSD=X']}
COST=0.0003; COST_LOW=0.0001
def load():
    import yfinance as yf; data={}
    for cls,ts in UNI.items():
        for t in ts:
            df=yf.download(t,period='730d',interval='1h',progress=False,auto_adjust=True,threads=False)
            if isinstance(df.columns,pd.MultiIndex): df.columns=df.columns.get_level_values(0)
            df=df.dropna(subset=['Close']); df.index=pd.to_datetime(df.index,utc=True)
            df=df[~df.index.duplicated()].sort_index()
            if len(df)<2000: print('skip',t,len(df)); continue
            if SYNTH:
                rng=np.random.default_rng(abs(hash(t))%2**32); r=rng.normal(0,df.Close.pct_change().std(),len(df)); df['Close']=100*np.exp(np.cumsum(r))
            data[(cls,t)]=df[['Close']].copy()
    return data
def hours(df): return df.index.hour
def in_range(h,a,n):  # hours a..a+n-1 mod 24
    return np.isin(h,[(a+i)%24 for i in range(n)])
def f_open(df,p):
    r=df.Close.pct_change(); h=hours(df); S,k,hold,d=p['S'],p['k'],p['hold'],p['dir']
    sig=np.sign(r.rolling(k).sum()).where(h==(S+k-1)%24)
    pos=sig.ffill(limit=hold-1).where(in_range(h,(S+k-1)%24,hold)).fillna(0)
    return d*pos
def f_overlap(df,p):
    r=df.Close.pct_change(); h=hours(df); lb,hold,d=p['lb'],p['hold'],p['dir']
    sig=np.sign(r.rolling(lb).sum()).where(h==12)
    return d*sig.ffill(limit=hold-1).where(in_range(h,12,hold)).fillna(0)
def f_last(df,p):
    r=df.Close.pct_change(); h=hours(df); S,d=p['S'],p['dir']
    n=20-S+1; sig=np.sign(r.rolling(n).sum()).where(h==19)
    return d*sig.where(h==19).fillna(0)
def f_overnight(df,p):
    h=hours(df); on=(h>=20)|(h<=12)
    return pd.Series(np.where(on if p['leg']=='overnight' else ~on,p['dir'],0),index=df.index,dtype=float)
def f_weekday(df,p):
    return pd.Series(np.where(df.index.dayofweek==p['d'],p['dir'],0),index=df.index,dtype=float)
def f_tom(df,p):
    days=pd.Series(df.index.normalize(),index=df.index); u=days.drop_duplicates(); ym=u.dt.to_period('M')
    idx=u.groupby(ym).cumcount(); cnt=u.groupby(ym).transform('size'); flag=((idx<3)|(idx>=cnt-2)); m=dict(zip(u,flag))
    return pd.Series([p['dir'] if m[d] else 0 for d in days],index=df.index,dtype=float)
def build():
    C=[]
    for S in (23,7,13):
        for k in (1,2):
            for hold in (2,4,6):
                for d in (1,-1): C.append((f"open_{S}_{k}_{hold}_{'c' if d>0 else 'f'}",f_open,dict(S=S,k=k,hold=hold,dir=d),'open_cont'))
    for lb in (2,3,6):
        for hold in (2,3):
            for d in (1,-1): C.append((f"overlap_{lb}_{hold}_{'c' if d>0 else 'f'}",f_overlap,dict(lb=lb,hold=hold,dir=d),'overlap'))
    for S in (13,14):
        for d in (1,-1): C.append((f"last_{S}_{'c' if d>0 else 'f'}",f_last,dict(S=S,dir=d),'last_hour'))
    for leg in ('overnight','day'):
        for d in (1,-1): C.append((f"{leg}_{'long' if d>0 else 'short'}",f_overnight,dict(leg=leg,dir=d),'overnight'))
    for wd in range(5):
        for d in (1,-1): C.append((f"wd{wd}_{'long' if d>0 else 'short'}",f_weekday,dict(d=wd,dir=d),'weekday'))
    for d in (1,-1): C.append((f"tom_{'long' if d>0 else 'short'}",f_tom,dict(dir=d),'tom'))
    return C
def backtest(df,pos,cost):
    ret=df.Close.pct_change().fillna(0); pos=pos.fillna(0).clip(-1,1).shift(1).fillna(0); turn=pos.diff().abs().fillna(0)
    return pos*ret-cost*turn, turn
def stats(pnl):
    pnl=pnl[pnl!=0] if (pnl!=0).sum()>50 else pnl
    if len(pnl)<100 or pnl.std()==0: return None
    yrs=max((pnl.index[-1]-pnl.index[0]).days/365.25,0.1); bpy=len(pnl)/yrs
    sh=pnl.mean()/pnl.std()*math.sqrt(bpy); t=pnl.mean()/(pnl.std()/math.sqrt(len(pnl))); eq=(1+pnl).cumprod(); dd=((eq/eq.cummax())-1).min()
    return dict(sharpe=sh,t=t,ret=eq.iloc[-1]-1,maxdd=dd,n=len(pnl))
def main():
    data=load(); cfgs=build(); print('assets',len(data),'| configs',len(cfgs),'| cells',len(cfgs)*len(data),'| synthetic' if SYNTH else '| real',flush=True)
    rows=[]; oos_ret={}
    for (cls,tk),df in data.items():
        mid=df.index[len(df)//2]
        for name,fn,p,fam in cfgs:
            try: pos=fn(df,p)
            except Exception as e: print('err',name,tk,repr(e)[:80]); continue
            pnl,turn=backtest(df,pos,COST); pnl_lo,_=backtest(df,pos,COST_LOW)
            ins=pnl[pnl.index<mid]; oos=pnl[pnl.index>=mid]; si=stats(ins); so=stats(oos); so_lo=stats(pnl_lo[pnl_lo.index>=mid])
            if not si or not so: continue
            rows.append(dict(config=name,family=fam,asset=tk,is_sharpe=si['sharpe'],oos_sharpe=so['sharpe'],oos_t=so['t'],oos_ret=so['ret'],oos_maxdd=so['maxdd'],oos_t_lowcost=so_lo['t'] if so_lo else None,trades_oos=int((turn[turn.index>=mid]>0).sum()),bars=len(df),oos_from=str(mid.date())))
            oos_ret[(name,tk)]=oos
    R=pd.DataFrame(rows); N=len(R); print(f"\n=== {N} cells | IS first half / OOS second half per instrument | cost {COST} per position change ===")
    from math import erf,sqrt
    pn=lambda x:0.5*(1+erf(x/sqrt(2)))
    for thr in (2.0,2.5,3.0,3.5): print(f"  OOS t >= {thr} AND IS positive: {len(R[(R.oos_t>=thr)&(R.is_sharpe>0)])} of {N} | chance {N*(1-pn(thr)):.1f}")
    print('\nTop 20 by OOS t:\n',R.sort_values('oos_t',ascending=False).head(20).round(3).to_string(index=False))
    print('\nBottom 5 by OOS t (the fade of a strong negative is a candidate too):\n',R.sort_values('oos_t').head(5).round(3).to_string(index=False))
    print('\nBy family (mean OOS Sharpe, pct positive):\n',R.groupby('family').agg(n=('oos_sharpe','size'),mean=('oos_sharpe','mean'),pct_pos=('oos_sharpe',lambda s:(s>0).mean())).round(3).to_string())
    surv=R[(R.oos_t>=3.0)&(R.is_sharpe>0)]
    print('\nSURVIVORS t>=3.0 and IS>0 (bootstrap 500):')
    rng=np.random.default_rng(1)
    for r in surv.itertuples():
        x=oos_ret[(r.config,r.asset)].values; x=x[x!=0] if (x!=0).sum()>50 else x; shs=[]
        for _ in range(500):
            s=rng.choice(x,size=len(x),replace=True); shs.append(s.mean()/s.std() if s.std()>0 else 0)
        p5,p50=np.percentile(shs,[5,50]); print(f"  {r.config} {r.asset}: oos_t {r.oos_t:.2f} lowcost_t {r.oos_t_lowcost} ret {r.oos_ret:.3f} dd {r.oos_maxdd:.3f} boot p5 {p5:.4f} -> {'SOLID' if p5>0 else 'FRAGILE'}")
    if not len(surv): print('  none')
    if not SYNTH:
        import psycopg2,psycopg2.extras; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
        con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
        cur.execute("CREATE TABLE IF NOT EXISTS v4_session (run_date DATE, config TEXT, family TEXT, asset TEXT, is_sharpe NUMERIC, oos_sharpe NUMERIC, oos_t NUMERIC, oos_ret NUMERIC, oos_maxdd NUMERIC, oos_t_lowcost NUMERIC, trades_oos INT, bars INT, oos_from DATE)")
        cur.execute("DELETE FROM v4_session WHERE run_date=current_date")
        psycopg2.extras.execute_values(cur,"INSERT INTO v4_session VALUES %s",[(datetime.date.today(),r.config,r.family,r.asset,*(None if v is None or (isinstance(v,float) and math.isnan(v)) else float(round(v,4)) for v in (r.is_sharpe,r.oos_sharpe,r.oos_t,r.oos_ret,r.oos_maxdd,r.oos_t_lowcost)),int(r.trades_oos),int(r.bars),r.oos_from) for r in R.itertuples()],page_size=1000)
        print('stored v4_session',N,'rows')
main()
PYFILE
python3 -m py_compile session_sweep.py || exit 1
echo "== synthetic leak test"; timeout 1200 python3 session_sweep.py --synthetic 2>&1 | grep -v Warning | sed -n 1,12p
echo; echo "== real run"; timeout 1500 python3 session_sweep.py 2>&1 | grep -v Warning
