#!/bin/bash
set -o pipefail
# 499_nonrunner_audit (Finder 2026-11-06, queue item 280, from 499_nonrunner_reaction): stress item 277's pass for look-ahead. A withdrawal is dated by the runner's last print, known only afterwards; a back struck before the removal has its price reduced, which neither job can price, so entries before the news are not real. Read only. No tables written. Rule is in the queue, fixed before this read.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,zlib,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line,step,back_hedge
from lib_official import fill,last_in,first_in,secs,checks
import lib_cand; lib_cand._checks(); checks()
def withdrawn(o,last_t,last_p,npre,inpl,others_after):
    return last_p<=10 and o-300*60<=last_t<=o-20*60 and npre>=3 and not inpl and others_after>=4
def repriced(entry,before,pN): return entry<=before*(1-0.5/pN)
# known answers: withdrawn at 4.0 implies a 25% cut, half of it 12.5%: favourite 2.0 to 1.75 is re-priced, to 1.76 is not.
assert repriced(1.75,2.0,4.0) and not repriced(1.76,2.0,4.0)
assert withdrawn(1000000,1000000-3000,5.0,4,False,6) and not withdrawn(1000000,1000000-600,5.0,4,False,6)
print("checks: OK",flush=True); T0=time.time()
pd.set_option('display.width',220); pd.set_option('display.max_columns',30)
def bet(ts,px,i,j,k=1):
    """Back at entry print i, out at exit print j, k ticks adverse each way."""
    a=step(fill(ts,px,i,'B'),-k)
    return None if a<=1.01 else back_hedge(a,step(float(px[j]),k-1))
# k=1 is the plain engine; k=3 is three ticks each way, back_hedge adding the last tick on exit: back 3.0 -> 2.94, exit 2.5 -> 2.56: 10*(2.94/2.56-1)=1.4844 less 2%
assert abs(back_hedge(step(3.0,-3),step(2.5,2))-10*(2.94/2.56-1)*.98)<1e-9
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
Q="sport='Horse Racing' AND market_type='WIN' AND country IN ('GB','IE') AND ltp>=1.01 AND ltp<1000"
C=Counter(); rows=[]; plc=[]
LEADS=[]
def score(R,W,tN,pN,o,m,plac):
    pr={}
    for s,(ts,px) in R.items():
        if s in W: continue
        i=last_in(ts,tN-1800,tN)
        if i is not None: pr[s]=float(px[i])
    if len(pr)<3: C[('P ' if plac else '')+'few prices before']+=1; return None
    f=min(pr,key=pr.get); ts,px=R[f]; i=first_in(ts,tN+180,tN+1200); j=last_in(ts,o-300,o-60)
    if i is None or j is None or ts[j]<=ts[i]: C[('P ' if plac else '')+'no fill or exit']+=1; return None
    e=float(px[i]); down=i>0 and px[i]<px[i-1]
    return (m,o,(o-tN)/60,pN,len(W),repriced(e,pr[f],pN),bool(down),(ts[i]-tN)/60,bet(ts,px,i,j,1),bet(ts,px,i,j,3),e/pr[f]-1)
for M0,M1 in zip(pd.date_range('2024-09-01','2026-09-01',freq='MS'),pd.date_range('2024-10-01','2026-10-01',freq='MS')):
    W_=" AND market_time>=%s AND market_time<%s"; pr_=(M0.to_pydatetime(),M1.to_pydatetime())
    A=pd.read_sql("SELECT market_id,market_time mt,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE "+Q+W_+" AND NOT inplay AND ts>=market_time-interval '320 minutes'",con,params=pr_)
    I=pd.read_sql("SELECT DISTINCT market_id,sel FROM bf_hist_other WHERE "+Q+W_+" AND inplay",con,params=pr_)
    Z=pd.read_sql("SELECT market_id,sel,count(*) n FROM bf_hist_other WHERE "+Q+W_+" AND NOT inplay GROUP BY 1,2",con,params=pr_)
    inpl=set(zip(I.market_id,I.sel)); npre={(m,s):int(n) for m,s,n in zip(Z.market_id,Z.sel,Z.n)}; del I,Z
    A['tt']=secs(A.ts); A['off']=secs(A.mt); A=A.sort_values('tt',kind='stable').drop_duplicates(['market_id','sel','tt'])
    for m,g in A.groupby('market_id',sort=False):
        o=float(g.off.iloc[0]); R={s:(y.tt.values,y.ltp.values) for s,y in g.groupby('sel',sort=False)}
        W=[s for s,(ts,px) in R.items() if withdrawn(o,float(ts[-1]),float(px[-1]),npre.get((m,s),0),(m,s) in inpl,sum(1 for z,(t2,_) in R.items() if z!=s and t2[-1]>ts[-1]))]
        if W:
            w=min(W,key=lambda s:R[s][0][-1]); tN=float(R[w][0][-1]); LEADS.append(o-tN)
            r=score(R,W,tN,float(R[w][1][-1]),o,m,False)
            if r: rows.append(r)
        elif LEADS:
            # placebo: a false date from the leads seen so far, a false withdrawn price of 5
            ld=LEADS[zlib.crc32(m.encode())%len(LEADS)]
            r=score(R,[],o-ld,5.0,o,m,True)
            if r: plc.append(r)
    del A; print(M0.date(),len(rows),len(plc),f"{time.time()-T0:.0f}s",flush=True)
con.close(); print("counted:",dict(C),flush=True)
cols='m off lead pN nw rp down wait v1 v3 jump'.split(); D=pd.DataFrame(rows,columns=cols); K=pd.DataFrame(plc,columns=cols)
assert not D.duplicated('m').any() and not K.duplicated('m').any()
md=float(np.median(D.off)); out=[]
def add(nm,x,c='v1'):
    z=x[x[c].notna()]
    if len(z)<30: out.append(dict(line=nm,n=len(z))); return
    l=line(z[c].astype(float).values,np.where(z.off<md,1,2)); out.append(dict(line=nm,n=l['n'],per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],PASS=l['PASS']))
add('277 ALL back, as run',D); add('single withdrawal',D[D.nw==1]); add('re-priced at entry',D[D.rp]); add('NOT yet re-priced',D[~D.rp])
S=D[(D.nw==1)&D.rp]; add('SINGLE + RE-PRICED, the test',S); add('SINGLE + RE-PRICED, 3 ticks',S,'v3'); add('SINGLE + RE-PRICED, down-print',S[S.down]); add('SINGLE + RE-PRICED, 10+ min wait',S[S.wait>=10])
add('SINGLE + RE-PRICED, lead over 120',S[S.lead>120*60/60]); add('SINGLE + RE-PRICED, lead 120 or under',S[S.lead<=120])
add('ALL, 3 ticks',D,'v3'); add('ALL, down-print',D[D.down]); add('ALL, not a down-print',D[~D.down])
add('PLACEBO all',K); add('PLACEBO down-print',K[K.down]); add('PLACEBO, 3 ticks',K,'v3')
L=pd.DataFrame(out); print(L.round(3).to_string(index=False))
print("share re-priced",round(float(D.rp.mean()),3),"placebo share passing the same test",round(float(K.rp.mean()),3))
print("by withdrawn price, SINGLE + RE-PRICED:",S.groupby(pd.cut(S.pN,[1,3,6,10.01]),observed=True).v1.agg(['size','mean']).round(3).to_dict('index'))
print("by half-year:",S.groupby(pd.to_datetime(S.off,unit='s').dt.to_period('2Q').astype(str)).v1.agg(['size','mean']).round(3).to_dict('index'))
print("\n== SURVIVORS"); P=L[(L.line=='SINGLE + RE-PRICED, the test')&(L.PASS==True)]; print(P.round(3).to_string(index=False) if len(P) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
