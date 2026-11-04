#!/bin/bash
set -o pipefail
# 499_luck_ou_old_seasons (Finder 2026-11-04, queue item 79, from jobs/499_luck_ou_fair_check.sh): the goal-line finishing-luck signal, N 5, cut 0.5 only, on 2012-13 to 2018-19, read by no test for this. Rule fixed in the queue first. Holds only if both states have the right sign and the spread between them has z >= 2.5. Points, no P&L, as these are not exchange prices. Price = de-vigged pre-match average (BbAv), else Bet365, so it is an earlier and noisier price than the close used in 2019-27.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,psycopg2,pandas as pd,numpy as np
from collections import defaultdict,deque
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import *
import lib_cand; lib_cand._checks()
pd.set_option('display.width',240); pd.set_option('display.max_rows',200); pd.set_option('display.max_columns',30)
SEASONS=('1213','1314','1415','1516','1617','1718','1819')
def num(x):
    try: v=float(x)
    except (TypeError,ValueError): return np.nan
    return v if 1<v<=1000 else np.nan
def signals(games,N,min_c=50):
    """Copy of jobs/499_finishing_luck.sh signals(), goal-line part: {index:(Gh,Ga)}, dates strictly before the game."""
    order=sorted(range(len(games)),key=lambda i:games[i]['date']); hist=defaultdict(lambda:deque(maxlen=N)); tg=ts=0; nc=0; out={}; i=0
    while i<len(order):
        j=i; d=games[order[i]]['date']
        while j<len(order) and games[order[j]]['date']==d: j+=1
        day=order[i:j]
        if nc>=min_c and ts>0:
            c=tg/ts
            for k in day:
                x=games[k]; h,a=hist[x['home']],hist[x['away']]
                if len(h)==N and len(a)==N: out[k]=tuple(np.mean([(q[0]-c*q[1])+(q[2]-c*q[3]) for q in t]) for t in (h,a))
        for k in day:
            x=games[k]
            if x['hst'] is None or x['ast'] is None or x['hst']!=x['hst'] or x['ast']!=x['ast']: continue
            hist[x['home']].append((x['hg'],x['hst'],x['ag'],x['ast'])); hist[x['away']].append((x['ag'],x['ast'],x['hg'],x['hst'])); tg+=x['hg']+x['ag']; ts+=x['hst']+x['ast']; nc+=1
        i=j
    return out
def state(a,b,cut=.5):
    m=(a+b)/2
    return 'due' if a<0 and b<0 and m<=-cut else 'ran' if a>0 and b>0 and m>=cut else None
def spread_z(k1,n1,p1,k2,n2,p2):
    """z of (won1-fair1)-(won2-fair2), variances from the fair prices."""
    v=p1*(1-p1)/n1+p2*(1-p2)/n2
    return ((k1/n1-p1)-(k2/n2-p2))/v**.5
_g=[dict(date=1,home='A',away='B',hg=2,ag=0,hst=4,ast=2),dict(date=2,home='B',away='A',hg=0,ag=1,hst=2,ast=4),dict(date=3,home='A',away='B',hg=9,ag=9,hst=1,ast=1)]
_s=signals(_g,2,2); assert list(_s)==[2] and abs(_s[2][0])<1e-9 and abs(_s[2][1])<1e-9
assert state(-.6,-.6)=='due' and state(.6,.6)=='ran' and state(-.2,-.2) is None and state(-1.,.1) is None and state(.5,.5)=='ran' and state(-.5,-.5)=='due'
# 55/100 v .5 and 45/100 v .5: difference 10 points, variance .005, z 1.41421
assert abs(spread_z(55,100,.5,45,100,.5)-(0.1/.005**.5))<1e-9
print("checks: OK",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='600s'")
D=pd.read_sql("SELECT div,season,date,home,away,fthg,ftag,hst,ast,raw FROM fd_matches WHERE fthg IS NOT NULL AND season=ANY(%s)",con,params=(list(SEASONS),)); con.close()
D['day']=pd.to_datetime(D.date); P=[]
for r in D.raw:
    got=(np.nan,np.nan,None)
    for src,a,b in (('BbAv','BbAv<2.5','BbAv>2.5'),('B365','B365<2.5','B365>2.5')):
        u,o=num(r.get(a)),num(r.get(b))
        if u==u and o==o: got=(u,o,src); break
    P.append(got)
D['u']=[p[0] for p in P]; D['o']=[p[1] for p in P]; D['src']=[p[2] for p in P]; D=D.drop(columns='raw')
print(f"games {len(D)}, shots present {D.hst.notna().mean():.3f}, priced {D.u.notna().mean():.3f}, sources {D.src.value_counts().to_dict()}, book {(1/D.o+1/D.u).mean():.4f}",flush=True)
D['over']=D.fthg+D.ftag>2.5; D['fair']=(1/D.o)/(1/D.o+1/D.u); rows=[]
for (dv,s),g in D.groupby(['div','season']):
    # all games build the history; only priced games can score
    g=g.reset_index(drop=True); games=[dict(date=x.day,home=x.home,away=x.away,hg=int(x.fthg),ag=int(x.ftag),hst=x.hst,ast=x.ast) for x in g.itertuples()]
    for k,(a,b) in signals(games,5).items():
        st=state(a,b)
        if st and g.fair.iloc[k]==g.fair.iloc[k]: rows.append((st,s,dv,bool(g.over.iloc[k]),g.fair.iloc[k]))
R=pd.DataFrame(rows,columns=['state','season','div','over','fair'])
o=[]
for st,x in R.groupby('state'): o.append(dict(state=st,n=len(x),games_div=x['div'].nunique(),won=x.over.mean(),fair=x.fair.mean(),pts=100*(x.over.mean()-x.fair.mean()),z=zscore(int(x.over.sum()),len(x),x.fair.mean())))
print("\n== N 5, cut 0.5, 2012-13 to 2018-19"); print(pd.DataFrame(o).round(4).to_string(index=False))
print("\n-- by season, points"); print(R.groupby(['season','state']).apply(lambda x:pd.Series(dict(n=len(x),pts=100*(x.over.mean()-x.fair.mean())))).unstack().round(2).to_string())
d,r=R[R.state=='due'],R[R.state=='ran']
z=spread_z(int(d.over.sum()),len(d),d.fair.mean(),int(r.over.sum()),len(r),r.fair.mean()); ptd,ptr=100*(d.over.mean()-d.fair.mean()),100*(r.over.mean()-r.fair.mean())
print(f"\n== VERDICT: due {ptd:+.2f}, over-ran {ptr:+.2f}, spread {ptd-ptr:+.2f} points, z {z:.2f}: {'HOLDS' if ptd>0 and ptr<0 and z>=2.5 else 'DOES NOT HOLD'} (bar fixed first: due > 0, over-ran < 0, z >= 2.5)")
PY
