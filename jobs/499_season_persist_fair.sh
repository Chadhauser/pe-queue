#!/bin/bash
set -o pipefail
# 499_season_persist_fair (Finder 2026-11-04, item 73 follow-up, defect from jobs/499_luck_ou_fair_check.sh): laying every game at Pinnacle's close +1 tick shows lay Over +0.107, lay Under +0.222 (t 3.97), both sides positive, so that fill collects Pinnacle's margin; on the exchange the same lays show -0.186 and +0.028. Item 73's FOLLOW lays at those closes. Same fit and same signal as jobs/499_season_goal_persist.sh, but judged without a fill: the laid side's win rate minus its de-vigged close, in points. Negative = the signal works. Also the P&L of laying EVERY rest-of-season game by source, so FOLLOW can be read against what the fill alone pays. Nothing else changed.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import *
import lib_cand; lib_cand._checks()
pd.set_option('display.width',240); pd.set_option('display.max_rows',200); pd.set_option('display.max_columns',30)
def num(x):
    try: v=float(x)
    except (TypeError,ValueError): return np.nan
    return v if v>1 else np.nan
def close(raw):
    for src,a,b in (('BFEC','BFEC<2.5','BFEC>2.5'),('PC','PC<2.5','PC>2.5'),('B365C','B365C<2.5','B365C>2.5')):
        u,o=num(raw.get(a)),num(raw.get(b))
        if u==u and o==o: return u,o,src
    return np.nan,np.nan,None
def fit_cut(dates): return dates[max(len(dates)//3-1,0)]
assert fit_cut(list(range(9)))==2 and fit_cut([1])==1 and abs(zscore(40,100,.5)+2)<1e-9
print("checks: OK",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='600s'")
D=pd.read_sql("SELECT div,season,date,fthg,ftag,raw FROM fd_matches WHERE fthg IS NOT NULL AND season>='1920' AND season<'9000'",con); con.close()
c=[close(r) for r in D.raw]; D['u']=[x[0] for x in c]; D['o']=[x[1] for x in c]; D['src']=[x[2] for x in c]; D=D.drop(columns='raw'); D=D[D.u.notna()].copy()
D['day']=pd.to_datetime(D.date); D['under']=(D.fthg+D.ftag)<2.5; D['fair']=(1/D.u)/(1/D.u+1/D.o); rows=[]
for (dv,s),g in D.groupby(['div','season']):
    if s=='2627': continue
    g=g.sort_values('day'); fc=fit_cut(list(g.day)); fit=g[g.day<=fc]; rest=g[g.day>fc]
    if len(fit)<60 or not len(rest): continue
    e=fit.under.mean()-fit.fair.mean()
    for r in rest.itertuples():
        lay_under=e<0; laid_won=r.under if lay_under else not r.under; laid_fair=r.fair if lay_under else 1-r.fair; px=r.u if lay_under else r.o
        rows.append((abs(e),r.src,s,laid_won,laid_fair,lay_settle(step(px,1),laid_won)))
R=pd.DataFrame(rows,columns=['e','src','season','won','fair','v']); o=[]
for cut in (.03,.05,.08):
    for lab,x in (('all',R[R.e>=cut]),('PC',R[(R.e>=cut)&(R.src=='PC')]),('BFEC',R[(R.e>=cut)&(R.src=='BFEC')])):
        o.append(dict(cut=cut,src=lab,n=len(x),per10=x.v.mean(),t=tstat(x.v),laid_won=x.won.mean(),fair=x.fair.mean(),pts=100*(x.won.mean()-x.fair.mean()),z=zscore(int(x.won.sum()),len(x),x.fair.mean())))
print("\n== FOLLOW, the laid side v its de-vigged close, negative pts = signal works; n should match item 73 (cut 3 17,135, cut 5 9,060, cut 8 1,629)"); print(pd.DataFrame(o).round(3).to_string(index=False))
# P&L of the fill alone: lay EVERY priced game in the same rest-of-season sets, Over and Under, by source
print("\n== lay everything, 2019-26, no signal"); A=D[D.season!='2627']
for s,x in A.groupby('src'):
    lo=[lay_settle(step(a,1),w) for a,w in zip(x.o,~x.under)]; lu=[lay_settle(step(a,1),w) for a,w in zip(x.u,x.under)]
    print(f"  {s}: n {len(x)} lay Over {np.mean(lo):+.3f} lay Under {np.mean(lu):+.3f} mean {np.mean(lo+lu):+.3f}")
PY
