#!/bin/bash
set -o pipefail
# 499_luck_ou_fair_check (Finder 2026-11-04, item 76 follow-up): in jobs/499_finishing_luck.sh every goal-line LAY is positive in BOTH directions, which suggests the fill and not the signal. A lay at a bookmaker's quote +1 tick collects that bookmaker's margin, a price no one offers.
# (A) unconditional: lay every Over and every Under at close +1 tick, by price source. If Pinnacle and Bet365 are positive on both sides and the exchange is not, those lay fills are fake. This also bears on jobs/499_season_goal_persist.sh (item 73), which lays at the same closes.
# (B) free of margin: Over 2.5 won minus de-vigged close, in points, by signal state, every N and cut, no choosing, so the signal is judged without any fill.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,psycopg2,pandas as pd,numpy as np
from collections import defaultdict,deque
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import *
import lib_cand; lib_cand._checks()
pd.set_option('display.width',240); pd.set_option('display.max_rows',200); pd.set_option('display.max_columns',30)
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
_g=[dict(date=1,home='A',away='B',hg=2,ag=0,hst=4,ast=2),dict(date=2,home='B',away='A',hg=0,ag=1,hst=2,ast=4),dict(date=3,home='A',away='B',hg=9,ag=9,hst=1,ast=1)]
_s=signals(_g,2,2); assert list(_s)==[2] and abs(_s[2][0])<1e-9 and abs(_s[2][1])<1e-9    # as the worked example in 499_finishing_luck: G = 0 for both
assert abs(zscore(60,100,.5)-2)<1e-9
print("checks: OK",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='600s'")
D=pd.read_sql("SELECT div,season,date,home,away,fthg,ftag,hst,ast,raw FROM fd_matches WHERE fthg IS NOT NULL AND season>='1920' AND season<'9000'",con); con.close()
D['day']=pd.to_datetime(D.date); P=[]
for r in D.raw:
    got=None
    for src,a,b in (('BFEC','BFEC<2.5','BFEC>2.5'),('PC','PC<2.5','PC>2.5'),('B365C','B365C<2.5','B365C>2.5')):
        u,o=num(r.get(a)),num(r.get(b))
        if u==u and o==o: got=(u,o,src); break
    P.append(got or (np.nan,np.nan,None))
D['u']=[p[0] for p in P]; D['o']=[p[1] for p in P]; D['src']=[p[2] for p in P]; D=D.drop(columns='raw'); D=D[D.u.notna()].reset_index(drop=True)
D['over']=D.fthg+D.ftag>2.5; D['fair']=(1/D.o)/(1/D.o+1/D.u)
print("\n== (A) lay everything at close +1 tick, by source, no signal")
for s,x in D.groupby('src'):
    lo=[lay_settle(step(a,1),w) for a,w in zip(x.o,x.over)]; lu=[lay_settle(step(a,1),not w) for a,w in zip(x.u,x.over)]
    print(f"  {s}: n {len(x)}, book {(1/x.o+1/x.u).mean():.4f}; lay Over {np.mean(lo):+.3f} t {tstat(lo):.2f}; lay Under {np.mean(lu):+.3f} t {tstat(lu):.2f}")
rows=[]
for (dv,s),g in D.groupby(['div','season']):
    g=g.reset_index(drop=True); games=[dict(date=x.day,home=x.home,away=x.away,hg=int(x.fthg),ag=int(x.ftag),hst=x.hst,ast=x.ast) for x in g.itertuples()]
    for N in (5,10):
        for k,(a,b) in signals(games,N).items():
            m=(a+b)/2; st=-1 if a<0 and b<0 else 1 if a>0 and b>0 else 0
            rows.append((N,s,g.src.iloc[k],m,st,bool(g.over.iloc[k]),g.fair.iloc[k]))
R=pd.DataFrame(rows,columns=['N','season','src','m','st','over','fair']); B={'1920':'19-22','2021':'19-22','2122':'19-22','2223':'22-25','2324':'22-25','2425':'22-25','2526':'2526','2627':'2627'}; R['band']=R.season.map(B)
print(f"\n== (B) Over 2.5 won minus de-vigged close, points; goals-due state = both teams' games below their shots; rows {len(R)}"); o=[]
for N in (5,10):
    for cut in (.3,.5,.8):
        for lab,x in (('goals due',R[(R.N==N)&(R.st==-1)&(R.m<=-cut)]),('goals over-ran',R[(R.N==N)&(R.st==1)&(R.m>=cut)])):
            d=dict(N=N,cut=cut,state=lab,n=len(x),pts=100*(x.over.mean()-x.fair.mean()),z=zscore(int(x.over.sum()),len(x),x.fair.mean()))
            for b in ('19-22','22-25','2526','2627'):
                y=x[x.band==b]; d[b]=100*(y.over.mean()-y.fair.mean()) if len(y) else np.nan
            y=x[x.src=='BFEC']; d['nBFEC']=len(y); d['BFEC']=100*(y.over.mean()-y.fair.mean()) if len(y) else np.nan; o.append(d)
print(pd.DataFrame(o).round(2).to_string(index=False))
a=R[R.N==5]; print(f"\n-- all games with a signal, N=5: {100*(a.over.mean()-a.fair.mean()):+.2f} points, n {len(a)}")
PY
