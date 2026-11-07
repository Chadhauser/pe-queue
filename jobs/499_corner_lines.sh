#!/bin/bash
set -o pipefail
# 499_corner_lines (Finder 2026-11-07, queue item 378, Finder's own, source d): corner lines, Over 8.5 goals and first-half 3.5 before the off, official results. Rule pushed before any price. Read only. LTP only, so a pass is an upper bound.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(1_500_000_000,1_500_000_000))  # this job only
import sys,time,warnings,psycopg2,pandas as pd,numpy as np
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,tstat,passes,back_settle,lay_settle
from lib_official import bk,ly
pd.set_option('display.width',230); pd.set_option('display.max_rows',150); pd.set_option('display.max_columns',30)
T0=time.time()
def side_of(s):
    t=str(s).strip().lower()
    return 'OVER' if t.startswith('over') else 'UNDER' if t.startswith('under') else None
def price_band(p): return '<2' if p<2 else '2-4' if p<4 else '4-10' if p<10 else '10+'
assert side_of('Over 8.5 Corners')=='OVER' and side_of('Under 10.5')=='UNDER' and side_of('x') is None
assert abs(bk(2.0,True)-10*.99*.98)<1e-9 and bk(2.0,False)==-10.0 and bk(1.02,True) is None and ly(2.0,True)==-10.0 and abs(ly(2.0,False)-10/1.02*.98)<1e-9
assert price_band(1.99)=='<2' and price_band(2)=='2-4' and price_band(4)=='4-10' and price_band(10)=='10+'
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
cur.execute("SELECT market_type,count(DISTINCT market_id) FROM bf_hist_result WHERE sport='Soccer' AND (market_type LIKE '%%CORNR%%' OR market_type IN ('OVER_UNDER_85','FIRST_HALF_GOALS_35')) GROUP BY 1 ORDER BY 2 DESC")
TY=cur.fetchall(); print("official results by type",TY,flush=True); types=[t for t,_ in TY]
if not types: print("\n== SURVIVORS: none; BLOCKED, bf_hist_result holds none of these market types, no price read"); sys.exit(0)
R=pd.read_sql("SELECT market_id,market_type,sel,status FROM bf_hist_result WHERE sport='Soccer' AND market_type=ANY(%s)",con,params=(types,))
w=R[R.status=='WINNER'].groupby('market_id').size(); ok=set(w[w==1].index); dropped=R.market_id.nunique()-len(ok); R=R[R.market_id.isin(ok)]; print(f"markets with one winner {len(ok)}, dropped {dropped}, {time.time()-T0:.0f}s",flush=True)
cur.execute("""SELECT DISTINCT ON (market_id,sel) market_id,market_type,event_name,market_time,sel,ltp::float8 FROM bf_hist_other WHERE sport='Soccer' AND market_type=ANY(%s) AND NOT inplay AND ltp>=1.01 AND ltp<=200 AND ts>=market_time-interval '15 minutes' AND ts<=market_time ORDER BY market_id,sel,ts""",(types,))
P=pd.DataFrame(cur.fetchall(),columns='market_id market_type event market_time sel p'.split()); con.close(); print(f"first prints T-15 to the off: {len(P):,}, markets {P.market_id.nunique():,}, {time.time()-T0:.0f}s",flush=True)
J=P.merge(R[['market_id','sel','status']],on=['market_id','sel']); J['o']=J.sel.map(side_of); un=int(J.o.isna().sum()); J=J[J.o.notna()].copy(); J['won']=J.status=='WINNER'
J['t']=(pd.to_datetime(J.market_time,utc=True)-pd.Timestamp('1970-01-01',tz='UTC'))/pd.Timedelta(seconds=1)
print(f"joined {len(J):,}; unknown runner {un}; {pd.to_datetime(J.t.min(),unit='s')} to {pd.to_datetime(J.t.max(),unit='s')}; by type {J.groupby('market_type').market_id.nunique().to_dict()}",flush=True)
assert not J.duplicated(['market_id','sel']).any()
J['B']=[bk(p,w) for p,w in zip(J.p,J.won)]; J['L']=[ly(p,w) for p,w in zip(J.p,J.won)]; J['B']=pd.to_numeric(J.B); J['pb']=J.p.map(price_band)
out=[]
def row(x,col,**k):
    x=x[x[col].notna()]; v=x[col].values
    if len(v)<30: return None
    md=np.median(x.t.values); h=x.t.values<md; a,b=v[h],v[~h]
    return dict(**k,n=len(v),games=x.event.nunique(),per10=v.mean(),t=tstat(v),n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,won=x.won.mean(),imp=(1/x.p).mean(),maxwin=v.max(),PASS=passes(len(v),len(a),len(b),tstat(v),a.mean() if len(a) else -1,b.mean() if len(b) else -1,v.mean()))
for (ty,o),x in J.groupby(['market_type','o']):
    for s,c in (('back','B'),('lay','L')):
        r=row(x,c,type=ty,run=o,band='ALL',side=s)
        if r: out.append(r)
        for b,y in x.groupby('pb'):
            r=row(y,c,type=ty,run=o,band=b,side=s)
            if r: out.append(r)
for o,x in J[J.market_type.str.contains('CORNR')].groupby('o'):
    for s,c in (('back','B'),('lay','L')):
        r=row(x,c,type='ALL_CORNERS',run=o,band='ALL',side=s)
        if r: out.append(r)
O=pd.DataFrame(out).sort_values('t',ascending=False); print(f"\n== ITEM 378: {len(O)} lines; top 25 by t\n",O.head(25).round(3).to_string(index=False)); print("\n== bottom 6\n",O.tail(6).round(3).to_string(index=False))
Z=O[O.PASS==True]; print(f"\n== SURVIVORS: {len(Z)} of {len(O)}\n",Z.round(3).to_string(index=False) if len(Z) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
