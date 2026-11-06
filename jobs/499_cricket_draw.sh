#!/bin/bash
set -o pipefail
# 499_cricket_draw (Finder 2026-11-06, queue item 289, Finder's own, source d; result method from jobs/499_cricket_truth.sh): three-runner cricket, pilot, cannot reach n 300. Rule pushed in the queue before any price. Read only. No tables written.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(1_500_000_000,1_500_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line
from lib_official import bk,ly,fill,last_in,secs,checks
import lib_cand; lib_cand._checks(); checks()
def infer3(last):
    lo=[k for k,v in last.items() if v<=1.10]
    if len(last)!=3 or len(lo)!=1: return None
    return lo[0] if all(v>=5.0 for k,v in last.items() if k!=lo[0]) else None
def q3(last,s):
    t=sum(1/v for v in last.values()); return (1/last[s])/t
assert infer3({'A':1.05,'B':20.,'The Draw':30.})=='A' and infer3({'A':1.05,'B':4.,'The Draw':30.}) is None and infer3({'A':1.05,'B':20.}) is None
assert abs(q3({'A':2.,'B':4.,'C':4.},'A')-.5)<1e-9
print("checks: OK",flush=True); T0=time.time()
pd.set_option('display.width',220); pd.set_option('display.max_columns',30)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
ID=pd.read_sql("SELECT market_id FROM bf_hist_other WHERE sport='Cricket' AND market_type='MATCH_ODDS' AND sel='The Draw' GROUP BY 1",con).market_id.tolist()
Q0="market_id=ANY(%s) AND ltp>=1.01 AND ltp<1000"
A=pd.read_sql("SELECT market_id,event_name ev,market_time mt,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE "+Q0+" AND NOT inplay AND ts>=market_time-interval '60 minutes'",con,params=(ID,))
B=pd.read_sql("SELECT DISTINCT ON (market_id,sel) market_id,sel,ltp::float8 ltp FROM bf_hist_other WHERE "+Q0+" AND inplay ORDER BY market_id,sel,ts DESC",con,params=(ID,)); con.close()
A['tt']=secs(A.ts); A['off']=secs(A.mt); A=A.sort_values('tt',kind='stable').drop_duplicates(['market_id','sel','tt']); LAST={m:dict(zip(g.sel,g.ltp)) for m,g in B.groupby('market_id')}
C=Counter(); rows=[]; seen=set()
for m,g in A.groupby('market_id',sort=True):
    ev=g.ev.iloc[0]; o=float(g.off.iloc[0])
    if (ev,o) in seen: C['second id']+=1; continue
    seen.add((ev,o)); last=LAST.get(m)
    if not last: C['no in-play prints, left out']+=1; continue
    if len(last)!=3: C['not three runners in play, left out']+=1; continue
    en={}
    for s,y in g.groupby('sel',sort=False):
        ts,px=y.tt.values,y.ltp.values; i=last_in(ts,o-3600,o-120)
        if i is not None: en[s]=(fill(ts,px,i,'B'),fill(ts,px,i,'L'),float(px[i]))
    if 'The Draw' not in en or len(en)<3: C['all three not priced']+=1; continue
    w=infer3(last); C['resolved' if w else 'unresolved']+=1
    tm=sorted([s for s in en if s!='The Draw'],key=lambda z:en[z][2]); roles={'DRAW':'The Draw','FAV':tm[0],'OUT':tm[1]}
    for r,s in roles.items():
        pb,pl,_=en[s]; vb=None; vl=None
        if w:
            if pb<=50: vb=bk(pb,s==w)
            if pl<=50: vl=ly(pl,s==w)
        else:
            q=q3(last,s)
            if pb<=50 and bk(pb,True) is not None: vb=q*bk(pb,True)+(1-q)*bk(pb,False)
            if pl<=50: vl=q*ly(pl,True)+(1-q)*ly(pl,False)
        rows.append((r,o,bool(w),None if not w else s==w,pb,pl,vb,vl))
print("counted:",dict(sorted(C.items())),flush=True)
D=pd.DataFrame(rows,columns='r off res won pb pl vb vl'.split()); md=float(np.median(D.off)); out=[]
for r,x in D.groupby('r'):
    for sd,c,pc in (('back','vb','pb'),('lay','vl','pl')):
        z=x[x[c].notna()]; l=line(z[c].astype(float).values,np.where(z.off<md,1,2)); rz=z[z.res]
        out.append(dict(line=r+' '+sd,n=l['n'],per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],resolved=len(rz),res_won=rz.won.astype(float).mean(),imp=(1/rz[pc]).mean(),PASS=l['PASS']))
L=pd.DataFrame(out); print("\n"+L.sort_values('t',ascending=False).round(3).to_string(index=False))
print("\n== SURVIVORS: none can pass here, pilot under n 300" if not L.PASS.any() else "\n== listed pass, check it"); print(f"total {time.time()-T0:.0f}s")
PY
