#!/bin/bash
set -o pipefail
# 499_sharp_gap_open_check (Finder 2026-11-04, item 75 follow-up): jobs/499_sharp_gap.sh reports 48 numeric passes, every one OPEN, LAY, tight False, at about +£17/£10, t about 25. A return that size on a two-way market is not believable. Question: are these prices real? If the BFE snapshot on a non-tight book is a thin quote far under any real lay, then "lay at x +1 tick" is a fill nobody offers.
# PRINTS for the OPEN v AVG lay 1% non-tight trades: which way the book is off, the price against the same runner's fair and close, how much of the P&L sits at short prices; then the same trades at a fill the market could offer: fair (average open, de-vigged) +1 tick, and exchange close +1 tick.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import *
import lib_cand; lib_cand._checks()
pd.set_option('display.width',240); pd.set_option('display.max_columns',30)
def num(x):
    try: v=float(x)
    except (TypeError,ValueError): return np.nan
    return v if 1<v<=1000 else np.nan
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='600s'")
D=pd.read_sql("SELECT season,date,fthg,ftag,raw FROM fd_matches WHERE fthg IS NOT NULL AND season IN ('2425','2526','2627')",con); con.close()
rows=[]
for g in D.itertuples():
    r=g.raw; res='H' if g.fthg>g.ftag else 'A' if g.ftag>g.fthg else 'D'; tot=g.fthg+g.ftag
    for sels,ex,be,cl in (('HDA','BFE','Avg','BFEC'),(('>2.5','<2.5'),'BFE','Avg','BFEC')):
        xs=[num(r.get(ex+s)) for s in sels]; bs=[num(r.get(be+s)) for s in sels]; cs=[num(r.get(cl+s)) for s in sels]
        if np.isnan(xs).any() or np.isnan(bs).any(): continue
        q=1/np.array(bs); f=q.sum()/q; ov=sum(1/x for x in xs)
        for s,x,fo,c in zip(sels,xs,f,cs):
            won=(s==res) if len(sels)==3 else ((tot>2.5)==(s=='>2.5'))
            rows.append((g.season,s,x,fo,c,ov,won))
R=pd.DataFrame(rows,columns=['season','sel','x','fair','close','ov','won'])
R['tight']=R.ov.between(.98,1.06); R['lay']=R.x<=R.fair/1.01
print("all books, sum of 1/x quantiles",R.ov.quantile([.01,.1,.5,.9,.99]).round(3).to_dict())
for lab,T in (('non-tight lay 1%',R[~R.tight&R.lay]),('tight lay 1%',R[R.tight&R.lay])):
    T=T.copy(); print(f"\n== {lab}: n {len(T)}; book over 1.06 {(T.ov>1.06).mean():.3f}, under 0.98 {(T.ov<.98).mean():.3f}")
    print("x quantiles",T.x.quantile([.1,.5,.9]).round(3).to_dict(),"x / fair median",round((T.x/T.fair).median(),3),"x / close median",round((T.x/T.close).median(),3))
    T['v']=[lay_settle(step(a,1),w) for a,w in zip(T.x,T.won)]
    print(f"at x +1 tick: {T.v.mean():+.3f} t {tstat(T.v):.2f}; won {T.won.mean():.3f}; 1/x {(1/T.x).mean():.3f}; 1/fair {(1/T.fair).mean():.3f}")
    print("by x band:"); print(T.groupby(pd.cut(T.x,[1,1.1,1.25,1.5,2,3,5,1000])).agg(n=('v','size'),per10=('v','mean'),won=('won','mean'),share_pnl=('v',lambda s:s.sum()/T.v.sum())).round(3).to_string())
    T['vf']=[lay_settle(step(a,1),w) for a,w in zip(T.fair,T.won)]; c=T[T.close.notna()].copy(); c['vc']=[lay_settle(step(a,1),w) for a,w in zip(c.close,c.won)]
    print(f"same trades at fair +1 tick: {T.vf.mean():+.3f} t {tstat(T.vf):.2f}; at exchange close +1 tick: n {len(c)} {c.vc.mean():+.3f} t {tstat(c.vc):.2f}")
PY
