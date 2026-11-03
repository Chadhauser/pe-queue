#!/bin/bash
# 503: FINANCIAL — the 7,000-cell INTRADAY GRAMMAR SWEEP Peter asked for (3 Nov 15:03). 12 triggers x 8 entry times x 2 directions x 5 holds
# x 8 instruments on 6.3 years of 1-minute Alpaca bars (~6,900 cells after availability). Synthetic control first (random trigger signs ->
# must be ~0 survivors), then real. Survivor = t>=3.5 & both halves >0 & n>=200. Table v4_intraday_grammar. Tested offline on fake data.
cd /root/pe-fin
cat > grammar_sweep.py <<'PYFILE'
# 503: INTRADAY GRAMMAR SWEEP on 1-minute Alpaca bars (8 instruments, Jul 2020 - Oct 2026). Every cell = TRIGGER x ENTRY TIME x
# DIRECTION x HOLD x INSTRUMENT. Triggers use only information up to the entry minute. Costs 2 bps round trip (ETF: 1c spread+1c slip
# on $100-500 names; MNQ-equivalent). IS = first half of days, OOS = second half; survivor = t>=3.5 AND both halves >0 AND n>=200.
# Threshold 3.5 for ~7,700 cells (expected by chance ~2). --synthetic randomises each day's trigger sign: must give ~chance survivors.
import sys, os, math, datetime, numpy as np, pandas as pd
pd.set_option('display.width',250); SYNTH='--synthetic' in sys.argv; FAKE='--fake' in sys.argv
SYMS=['QQQ','SPY','IWM','TLT','GLD','USO','TQQQ','SQQQ']; COST=0.0002; NMIN=390
def day_matrix(sym):
    """returns (dates, C[n_days,390], O0[n_days] open, prevclose[n_days]) on a 09:30-16:00 NY minute grid, ffilled within day"""
    if FAKE:
        rng=np.random.default_rng(abs(hash(sym))%2**32); nd=1500; r=rng.normal(0,0.0004,(nd,NMIN)); C=100*np.exp(np.cumsum(r,axis=1)+np.cumsum(rng.normal(0,0.01,nd))[:,None])
        return pd.bdate_range('2020-07-27',periods=nd), C, C[:,0]*(1+rng.normal(0,0.001,nd)), np.r_[C[0,0],C[:-1,-1]]
    sys.path.insert(0,'/root/pe-fin'); from alpaca_load import load
    b=load(sym); ny=b.index.tz_convert('America/New_York'); mi=(ny.hour*60+ny.minute)-570
    b=b[(mi>=0)&(mi<NMIN)]; mi=mi[(mi>=0)&(mi<NMIN)]; d=pd.Index(ny[(ny.hour*60+ny.minute-570>=0)&(ny.hour*60+ny.minute-570<NMIN)].date)
    df=pd.DataFrame({'d':d,'m':mi,'c':b.close.values,'o':b.open.values})
    P=df.pivot_table(index='d',columns='m',values='c',aggfunc='last').reindex(columns=range(NMIN))
    ok=P.notna().sum(axis=1)>=200; P=P[ok]; P=P.ffill(axis=1).bfill(axis=1)
    O0=df[df.m==df.groupby('d').m.transform('min')].groupby('d').o.first().reindex(P.index).values
    C=P.values; prev=np.r_[np.nan,C[:-1,-1]]
    return pd.DatetimeIndex(P.index), C, O0, prev
ENTRY={'0935':5,'1000':30,'1030':60,'1100':90,'1300':210,'1400':270,'1500':330,'1530':360}; HOLD={'15':15,'30':30,'60':60,'120':120,'close':None}
def triggers(C,O0,prev,m):
    """dict name -> sign array (+1/-1/0) using info up to minute m"""
    T={}; close=C[:,m]
    for k in (5,15,30):
        if m>=k: T[f'orb{k}']=np.sign(C[:,k-1]-O0)
    gap=(O0/prev-1)
    for thr in (0.002,0.005,0.01): T[f'gap{int(thr*1e4)}']=np.where(np.abs(gap)>=thr,np.sign(gap),0)
    for h in (30,60):
        if m>=h: T[f'mom{h}']=np.sign(close-C[:,m-h])
    twap=C[:,:m+1].mean(axis=1); dev=close/twap-1
    for thr in (0.002,0.005): T[f'twap{int(thr*1e4)}']=np.where(np.abs(dev)>=thr,np.sign(dev),0)
    hi=C[:,:m+1].max(axis=1); lo=C[:,:m+1].min(axis=1); T['rangepos']=np.sign(close-(hi+lo)/2)
    pp=np.r_[np.nan,prev[:-1]]; T['prevday']=np.sign(prev-pp)
    return T
rows=[]; rng=np.random.default_rng(11)
for sym in SYMS:
    dates,C,O0,prev=day_matrix(sym); nd=len(dates); half=nd//2
    print(f"{sym}: days {nd} | {dates[0].date()} -> {dates[-1].date()}",flush=True)
    for en,m in ENTRY.items():
        T=triggers(C,O0,prev,m); entry=C[:,m]
        for hn,h in HOLD.items():
            ex=C[:,NMIN-1] if h is None else C[:,min(NMIN-1,m+h)]
            ret=ex/entry-1
            for tn,sig in T.items():
                s=sig.copy()
                if SYNTH: s=s*rng.choice([-1,1],size=len(s))
                for dn,dirn in (('with',1),('against',-1)):
                    p=dirn*s*ret-COST*(s!=0); use=(s!=0)&np.isfinite(p)
                    n=int(use.sum())
                    if n<60: continue
                    x=p[use]; t=x.mean()/(x.std(ddof=1)/math.sqrt(n)) if x.std()>0 else 0
                    h1=p[:half][use[:half]]; h2=p[half:][use[half:]]
                    rows.append(dict(sym=sym,trigger=tn,entry=en,direction=dn,hold=hn,n=n,mean_bps=round(1e4*x.mean(),2),t=round(t,2),h1_bps=round(1e4*h1.mean(),2) if len(h1) else None,h2_bps=round(1e4*h2.mean(),2) if len(h2) else None))
R=pd.DataFrame(rows); R['survivor']=(R.t>=3.5)&(R.h1_bps>0)&(R.h2_bps>0)&(R.n>=200)
print(f"\n=== {'SYNTHETIC' if SYNTH else 'REAL'}: cells {len(R)} | survivors t>=3.5 & both halves>0 & n>=200: {int(R.survivor.sum())} | chance at t>=3.5 one-sided ~{len(R)*0.00023:.1f} | cells t<=-3.5 (reverse-direction duplicates) {(R.t<=-3.5).sum()}")
print("\nTOP 25 by t:"); print(R.sort_values('t',ascending=False).head(25).to_string(index=False))
if not SYNTH: print("\nSURVIVORS:"); print(R[R.survivor].sort_values('t',ascending=False).to_string(index=False))
print("\nby trigger family (mean t of best direction):"); print(R.groupby('trigger').t.agg(['count','max','mean']).round(2).to_string())
if not SYNTH and not FAKE:
    import psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
    con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
    cur.execute("CREATE TABLE IF NOT EXISTS v4_intraday_grammar (run_date DATE, sym TEXT, trigger TEXT, entry TEXT, direction TEXT, hold TEXT, n INT, mean_bps NUMERIC, t NUMERIC, h1_bps NUMERIC, h2_bps NUMERIC, survivor BOOLEAN)")
    cur.execute("DELETE FROM v4_intraday_grammar WHERE run_date=current_date")
    import psycopg2.extras; psycopg2.extras.execute_values(cur,"INSERT INTO v4_intraday_grammar VALUES %s",[(datetime.date.today(),r.sym,r.trigger,r.entry,r.direction,r.hold,int(r.n),float(r.mean_bps),float(r.t),None if r.h1_bps is None else float(r.h1_bps),None if r.h2_bps is None else float(r.h2_bps),bool(r.survivor)) for r in R.itertuples()])
    print("stored v4_intraday_grammar",len(R))
PYFILE
python3 -m py_compile grammar_sweep.py || exit 1
echo "== SYNTHETIC CONTROL"; timeout 2400 python3 grammar_sweep.py --synthetic 2>&1 | grep -v Warning | grep -E "===|days"
echo; echo "== REAL"; timeout 3000 python3 grammar_sweep.py 2>&1 | grep -v Warning
