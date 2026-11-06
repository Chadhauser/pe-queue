#!/bin/bash
set -o pipefail
# READ WITH item 280: the lines this job lists as SURVIVORS are look-ahead, single + re-priced -0.395 t -6.08. See 499_nonrunner_audit.
# 499_nonrunner_reaction (Finder 2026-11-06, queue item 277, Finder's own, source a): does the favourite overshoot after a withdrawal? Closed before the off at real prints. A withdrawal is inferred from the tape, no official list is on the box. Read only. No tables written. Rule is in the queue, fixed before prices.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line,step,back_hedge,lay_hedge
from lib_official import fill,last_in,first_in,secs,checks
import lib_cand; lib_cand._checks(); checks()
def withdrawn(o,last_t,last_p,npre,inpl,others_after):
    """Tape rule for a non-runner, from the queue."""
    return last_p<=10 and o-300*60<=last_t<=o-20*60 and npre>=3 and not inpl and others_after>=4
assert withdrawn(1000000,1000000-3000,5.0,4,False,6) and not withdrawn(1000000,1000000-3000,12.0,4,False,6)
assert not withdrawn(1000000,1000000-600,5.0,4,False,6) and not withdrawn(1000000,1000000-3000,5.0,4,True,6) and not withdrawn(1000000,1000000-3000,5.0,2,False,6) and not withdrawn(1000000,1000000-3000,5.0,4,False,3)
print("checks: OK",flush=True); T0=time.time()
pd.set_option('display.width',220); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',200)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
# Fixed once 2026-11-06: the one big read ran out of memory, so read by month. The rule is unchanged.
Q="sport='Horse Racing' AND market_type='WIN' AND country IN ('GB','IE') AND ltp>=1.01 AND ltp<1000"
C=Counter(); rows=[]; ctrl=[]
for M0,M1 in zip(pd.date_range('2024-09-01','2026-09-01',freq='MS'),pd.date_range('2024-10-01','2026-10-01',freq='MS')):
    W_=" AND market_time>=%s AND market_time<%s"; pr_=(M0.to_pydatetime(),M1.to_pydatetime())
    A=pd.read_sql("SELECT market_id,market_time mt,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE "+Q+W_+" AND NOT inplay AND ts>=market_time-interval '320 minutes'",con,params=pr_)
    I=pd.read_sql("SELECT DISTINCT market_id,sel FROM bf_hist_other WHERE "+Q+W_+" AND inplay",con,params=pr_)
    Z=pd.read_sql("SELECT market_id,sel,count(*) n FROM bf_hist_other WHERE "+Q+W_+" AND NOT inplay GROUP BY 1,2",con,params=pr_)
    print(M0.date(),"rows",len(A),"markets",A.market_id.nunique(),f"{time.time()-T0:.0f}s",flush=True)
    inpl=set(zip(I.market_id,I.sel)); npre={(m,s):int(n) for m,s,n in zip(Z.market_id,Z.sel,Z.n)}; del I,Z
    A['tt']=secs(A.ts); A['off']=secs(A.mt); A=A.sort_values('tt',kind='stable').drop_duplicates(['market_id','sel','tt'])
    for m,g in A.groupby('market_id',sort=False):
        o=float(g.off.iloc[0]); R={s:(y.tt.values,y.ltp.values) for s,y in g.groupby('sel',sort=False)}; C['markets']+=1
        W=[]
        for s,(ts,px) in R.items():
            after=sum(1 for z,(t2,_) in R.items() if z!=s and t2[-1]>ts[-1])
            if withdrawn(o,float(ts[-1]),float(px[-1]),npre.get((m,s),0),(m,s) in inpl,after): W.append(s)
        if not W:
            # control: favourite at T-60, same exit
            pr={s:float(px[i]) for s,(ts,px) in R.items() for i in [last_in(ts,o-3900,o-3600)] if i is not None}
            if len(pr)<4: C['control few prices']+=1; continue
            f=min(pr,key=pr.get); ts,px=R[f]; i=first_in(ts,o-3600,o-3300); j=last_in(ts,o-300,o-60)
            if i is None or j is None: C['control no fill or exit']+=1; continue
            ctrl.append((m,o,'CONTROL',back_hedge(step(fill(ts,px,i,'B'),-1),float(px[j])) if step(fill(ts,px,i,'B'),-1)>1.01 else None,lay_hedge(step(fill(ts,px,i,'L'),1),float(px[j])),float(px[j])/float(px[i])-1)); continue
        C['races with a withdrawal']+=1
        if len(W)>1: C['more than one, first taken']+=1
        w=min(W,key=lambda s:R[s][0][-1]); tN=float(R[w][0][-1]); pN=float(R[w][1][-1])
        pr={}
        for s,(ts,px) in R.items():
            if s in W: continue
            i=last_in(ts,tN-1800,tN)
            if i is not None: pr[s]=float(px[i])
        if len(pr)<3: C['few prices before']+=1; continue
        f=min(pr,key=pr.get); ts,px=R[f]; i=first_in(ts,tN+180,tN+1200); j=last_in(ts,o-300,o-60)
        if i is None or j is None or ts[j]<=ts[i]: C['no fill or exit']+=1; continue
        b='<=3' if pN<=3 else '3-6' if pN<=6 else '6-10'; ab,al=step(fill(ts,px,i,'B'),-1),step(fill(ts,px,i,'L'),1)
        rows.append((m,o,b,back_hedge(ab,float(px[j])) if ab>1.01 else None,lay_hedge(al,float(px[j])),float(px[j])/float(px[i])-1,float(px[i])/pr[f]-1))
    del A
con.close()
print("counted:",dict(C),flush=True)
D=pd.DataFrame(rows,columns='m off b vb vl mv jump'.split()); K=pd.DataFrame(ctrl,columns='m off b vb vl mv'.split())
assert not D.duplicated('m').any() and not K.duplicated('m').any()
md=float(np.median(D.off)); out=[]
print("favourite's jump, last print before the withdrawal to entry, mean by band:",D.groupby('b').jump.agg(['size','mean','median']).round(4).to_dict('index'),flush=True)
print("share of withdrawals where the favourite shortened:",round(float((D.jump<0).mean()),3))
for nm,x in [('ALL',D)]+[(b,D[D.b==b]) for b in ('<=3','3-6','6-10')]+[('CONTROL',K)]:
    for sd,c in (('back','vb'),('lay','vl')):
        z=x[x[c].notna()]
        if len(z)<30: continue
        l=line(z[c].astype(float).values,np.where(z.off<md,1,2)); out.append(dict(line=nm+' '+sd,n=l['n'],per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],mean_move=x.mv.mean(),PASS=l['PASS']))
L=pd.DataFrame(out); print(L.round(3).to_string(index=False))
print("\n== SURVIVORS"); P=L[L.PASS&~L.line.str.startswith('CONTROL')]; print(P.round(3).to_string(index=False) if len(P) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
