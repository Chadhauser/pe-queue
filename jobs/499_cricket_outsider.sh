#!/bin/bash
set -o pipefail
# 499_cricket_outsider (Finder 2026-11-06, queue item 271, Finder's own, source a; from jobs/499_cricket_preoff.sh): item 268's three best lines are one idea, so read it once, one bet per game, and stress the inferred result. On the SAME months that suggested it, so this cannot pass: it says only whether the idea is worth a fixed rule on unseen months. Read only. No tables written.
# LINE two-runner cricket, lay the outsider at 3-20, last non-in-play print T-60 to T-2, worse of it and the next within 120 s, one tick adverse, 2%, GBP 10 liability, hold to the result. Three result rules: as 268 (winner <= 1.10, loser >= 5), strict (<= 1.03, >= 20), and 268 with unresolved games counted at the entry's own implied odds, which gives them no edge either way bar costs.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line,step
from lib_official import ly,fill,last_in,secs,checks
import lib_cand; lib_cand._checks(); checks()
def infer(last,lo_,hi_):
    lo=[k for k,v in last.items() if v<=lo_]
    if len(lo)!=1 or len(last)!=2: return None
    return lo[0] if all(v>=hi_ for k,v in last.items() if k!=lo[0]) else None
assert infer({'a':1.05,'b':20},1.10,5.0)=='a' and infer({'a':1.05,'b':19},1.03,20.0) is None and infer({'a':1.02,'b':20},1.03,20.0)=='a' and infer({'a':1.02},1.10,5.0) is None
def zero_edge(p):
    """Lay at fill step(p,1) with the runner winning at exactly 1/fill: the expected P&L is the commission alone. By hand at fill 5: stake 2.5, win 2.45 with 0.8, lose 10 with 0.2: 1.96-2.0 = -0.04."""
    f=step(p,1); q=1/f; return (1-q)*ly(p,False)+q*ly(p,True)
assert abs(zero_edge(4.9)-(-0.04))<1e-9   # step(4.9,1) is 5.0
print("checks: OK",flush=True); T0=time.time()
pd.set_option('display.width',220); pd.set_option('display.max_columns',30)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
Q0="sport='Cricket' AND market_type='MATCH_ODDS' AND ltp>=1.01 AND ltp<1000 AND market_time>='2024-09-01'"
A=pd.read_sql("SELECT market_id,event_name ev,market_time mt,sel,ts,ltp::float8 ltp,inplay FROM bf_hist_other WHERE "+Q0+" AND NOT inplay AND ts>=market_time-interval '60 minutes'",con)
B=pd.read_sql("SELECT DISTINCT ON (market_id,sel) market_id,event_name ev,market_time mt,sel,ts,ltp::float8 ltp,inplay FROM bf_hist_other WHERE "+Q0+" AND inplay AND ts<=market_time+interval '12 hours' ORDER BY market_id,sel,ts DESC",con); con.close()
P=pd.concat([A,B],ignore_index=True); del A,B
P['tt']=secs(P.ts); P['off']=secs(P.mt); P=P.sort_values('tt',kind='stable').drop_duplicates(['market_id','sel','tt','inplay'])
C=Counter(); rows=[]; seen=set()
for m,g in P.groupby('market_id',sort=True):
    ev=g.ev.iloc[0]; o=float(g.off.iloc[0])
    if (ev,o) in seen: C['second id']+=1; continue
    seen.add((ev,o)); runners=g.sel.unique()
    if len(runners)!=2: C['not two runners']+=1; continue
    pre=g[~g.inplay]; last=g[g.inplay].groupby('sel').ltp.last().to_dict(); en={}
    for s,y in pre.groupby('sel',sort=False):
        ts,px=y.tt.values,y.ltp.values; i=last_in(ts,o-3600,o-120)
        if i is not None: en[s]=(float(px[i]),ts,px,i)
    if len(en)!=2: C['both runners not priced']+=1; continue
    a,b=sorted(en,key=lambda z:en[z][0]);
    if en[a][0]==en[b][0]: C['level']+=1; continue
    _,ts,px,i=en[b]; p=fill(ts,px,i,'L')
    if not 3.0<=p<20.0: C['outsider outside 3-20']+=1; continue
    w1,w2=infer(last,1.10,5.0),infer(last,1.03,20.0); ze=zero_edge(p)
    v1=None if w1 is None else ly(p,w1==b); v2=None if w2 is None else ly(p,w2==b)
    k3=None if w1 is None else ly(step(p,2),w1==b); k5=None if w1 is None else ly(step(p,4),w1==b)
    up=(i>0 and px[i]>px[i-1]); age=(o-ts[i])/60; ol=last.get(b); fl=last.get(a)
    rows.append((ev,o,p,v1,v2,v1 if v1 is not None else ze,w1 is None,k3,k5,up,age,ol,fl))
print("counted:",dict(sorted(C.items())),flush=True)
R=pd.DataFrame(rows,columns='e off p v1 v2 v3 un k3 k5 up age ol fl'.split()); assert not R.duplicated(['e','off']).any(); md=np.median(R.off.values); print("games",len(R),"halves split at",pd.Timestamp(md,unit='s',tz='UTC'),"unresolved",int(R.un.sum()),flush=True)
out=[]
for nm,c in (('268 rule, resolved only','v1'),('strict rule, resolved only','v2'),('268 rule, unresolved at zero edge','v3')):
    x=R[R[c].notna()]; l=line(x[c].values,np.where(x.off<md,1,2)); out.append(dict(line=nm,n=l['n'],per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],maxwin=l['maxwin'],bar_on_these_months=l['PASS']))
print(pd.DataFrame(out).round(3).to_string(index=False))
x=R[R.v1.notna()]; print("\nby price, 268 rule:",x.groupby(pd.cut(x.p,[3,4,6,10,20],right=False),observed=True).v1.agg(['size','mean']).round(3).to_dict('index'))
print("by half-year:",x.groupby(pd.to_datetime(x.off,unit='s').dt.to_period('2Q').astype(str)).v1.agg(['size','mean']).round(3).to_dict('index'))
print("\n== stress, 268 rule")
s=[]
for nm,x_,c in (('3 ticks adverse',R[R.k3.notna()],'k3'),('5 ticks adverse',R[R.k5.notna()],'k5'),('entry is an up-print',R[R.v1.notna()&R.up],'v1'),('entry not an up-print',R[R.v1.notna()&~R.up],'v1'),('print T-15 or later',R[R.v1.notna()&(R.age<=15)],'v1'),('print before T-15',R[R.v1.notna()&(R.age>15)],'v1')):
    l=line(x_[c].values,np.where(x_.off<md,1,2)); s.append(dict(line=nm,n=l['n'],per10=l['per10'],t=l['t'],h1=l['h1'],h2=l['h2']))
print(pd.DataFrame(s).round(3).to_string(index=False))
print("print age before the off, minutes, p25 p50 p75:",R.age.quantile([.25,.5,.75]).round(1).tolist())
U=R[R.un]; bo=(U.ol.notna()&U.fl.notna()); lead=(U.ol<U.fl)[bo]
print(f"unresolved {len(U)}; both runners with a last in-play print {int(bo.sum())}; outsider's last print below the favourite's {int(lead.sum())}, share {lead.mean():.3f}; no in-play print on a runner {int((~bo).sum())}")
tot=x.v1.sum(); print(f"resolved P&L {tot:.0f}; outsider wins among the {len(U)} unresolved that would take the whole line to zero: {tot/10:.0f}, share {tot/10/len(U):.3f}; entry implied mean {(1/U.p).mean():.3f}")
print("\n== SURVIVORS: none can pass here, these months suggested the line"); print(f"total {time.time()-T0:.0f}s")
PY
