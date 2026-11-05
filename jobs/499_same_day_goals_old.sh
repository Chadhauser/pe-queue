#!/bin/bash
set -o pipefail
# 499_same_day_goals_old (Finder 2026-11-05, queue item 183, from jobs/499_same_day_goals.sh): SD signal on 2019-20 to 2023-24 at Pinnacle closes. Bar pushed to the queue before these prices were read. A support test: closes are not exchange prices, so nothing here can pass; points first, P&L for reading only.
# SIGNAL same div and season, same date, kicked off at least 115 minutes earlier by raw Time, n>=2, mean goals >=3.5. Time and date are as football-data gives them, one clock within a div, so the gap is sound though item 180 used UTC.
# HOLDS only if SD HIGH points > 0 in both 1920-2122 and 2223-2324, z >= 2.5 overall, and spread v SD not HIGH z >= 2.0. z from the fair prices.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,back_settle,zscore,line
import lib_cand; lib_cand._checks()
pd.set_option('display.width',220); pd.set_option('display.max_rows',100)
T0=time.time(); GAP=115; EARLY=('1920','2021','2122'); LATE=('2223','2324')
def num(x):
    try: v=float(x)
    except (TypeError,ValueError): return np.nan
    return v if 1<v<=1000 else np.nan
def mins(s):
    try: h,m=str(s).split(':')[:2]; return int(h)*60+int(m)
    except (ValueError,AttributeError): return None
def sd(tm,gl,K):
    """tm minutes and gl goals for the other games that day in the div. True or False with at least 2 games kicked off at least GAP earlier, else None."""
    g=[a for t,a in zip(tm,gl) if t<=K-GAP]
    return None if len(g)<2 else float(np.mean(g))>=3.5
def fair(o,u): return (1/o)/(1/o+1/u)
def spread_z(k1,n1,p1,k2,n2,p2): return ((k1/n1-p1)-(k2/n2-p2))/(p1*(1-p1)/n1+p2*(1-p2)/n2)**.5
def holds(p_e,p_l,z,sz): return bool(p_e>0 and p_l>0 and z>=2.5 and sz>=2.0)
# known answers, worked by hand
assert mins('15:00')==900 and mins('')is None and mins(None) is None and num('2.5')==2.5 and num('')!=num('') and num('1.0')!=num('1.0')
assert sd([720,780],[4,3],900) is True and sd([720,780],[1,1],900) is False and sd([720],[9],900) is None and sd([720,800],[9,9],900) is None  # 800 is only 100 minutes before 900
assert sd([720,785],[4,3],900) is True    # 785 is exactly 115 before
assert abs(fair(2.0,2.0)-0.5)<1e-12 and abs(fair(1.5,3.0)-2/3)<1e-12
assert abs(spread_z(55,100,.5,45,100,.5)-(0.1/.005**.5))<1e-9
assert holds(.1,.1,2.5,2.0) and not holds(-.1,.1,9,9) and not holds(.1,-.1,9,9) and not holds(.1,.1,2.49,9) and not holds(.1,.1,9,1.99)
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='600s'")
D=pd.read_sql("SELECT div,season,date,fthg,ftag,raw->>'Time' tm,raw->>'PC>2.5' o,raw->>'PC<2.5' u FROM fd_matches WHERE fthg IS NOT NULL AND ftag IS NOT NULL AND season=ANY(%s)",con,params=(list(EARLY+LATE),)); con.close()
D['t']=D.tm.map(mins); D['o']=D.o.map(num); D['u']=D.u.map(num); D['g']=D.fthg+D.ftag; D['over']=D.g>2.5
print(f"games {len(D)}, no Time {D.t.isna().sum()}, no close {(D.o.isna()|D.u.isna()).sum()}",flush=True)
sig=[]
for _,x in D.groupby(['div','season','date'],sort=False):
    known=x[x.t.notna()]
    for i,r in zip(x.index,x.itertuples()):
        s=None
        if r.t==r.t:
            o=known.drop(index=i); s=sd(o.t.values,o.g.values,r.t)
        sig.append((i,s))
D['sig']=pd.Series(dict(sig),dtype=object)
P=D[D.o.notna()&D.u.notna()].copy(); P['fair']=fair(P.o,P.u); P['per']=np.where(P.season.isin(EARLY),1,2); P['v']=[back_settle(step(a,-1),w) if step(a,-1)>1.01 else np.nan for a,w in zip(P.o,P.over)]; P=P[P.v.notna()]
def pts(x): return 100*(x.over.mean()-x.fair.mean())
def rep(name,x):
    l=line(x.v.values,x.per.values); z=zscore(int(x.over.sum()),len(x),x.fair.mean())
    print(f"  {name}: n {len(x)} won {x.over.mean():.4f} fair {x.fair.mean():.4f} pts {pts(x):+.2f} (early {pts(x[x.per==1]):+.2f} n {int((x.per==1).sum())}, late {pts(x[x.per==2]):+.2f} n {int((x.per==2).sum())}) z {z:.2f} | P&L at the close per10 {l['per10']:+.3f} t {l['t']:.2f} h1 {l['h1']:+.3f} h2 {l['h2']:+.3f}")
    return z
Hi=P[P.sig==True]; Lo=P[P.sig==False]; No=P[P.sig.isna()]
print("== lines"); z=rep('SD HIGH',Hi); rep('SD not HIGH',Lo); rep('no SD signal',No); rep('every game',P)
sz=spread_z(int(Hi.over.sum()),len(Hi),Hi.fair.mean(),int(Lo.over.sum()),len(Lo),Lo.fair.mean())
print(f"  spread SD HIGH v not HIGH {pts(Hi)-pts(Lo):+.2f} points, z {sz:.2f}")
print("== SD HIGH by season, points"); print(Hi.groupby('season').apply(lambda x:pd.Series(dict(n=len(x),pts=round(pts(x),2)))).to_string())
print("== SD HIGH by div, top and bottom 4 by points, n>=50"); B=Hi.groupby('div').apply(lambda x:pd.Series(dict(n=len(x),pts=round(pts(x),2)))); B=B[B.n>=50].sort_values('pts'); print(pd.concat([B.tail(4),B.head(4)]).to_string())
ok=holds(pts(Hi[Hi.per==1]),pts(Hi[Hi.per==2]),z,sz)
print(f"== VERDICT: {'HOLDS' if ok else 'DOES NOT HOLD'} (bar fixed first: points > 0 in both periods, z >= 2.5, spread z >= 2.0)")
print("== SURVIVORS: a support test, none can pass")
print(f"done {time.time()-T0:.0f}s")
PY
