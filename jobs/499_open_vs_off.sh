#!/bin/bash
set -o pipefail
# READ WITH item 281: the one line this job lists as a SURVIVOR is junk prints, and this job does not drop a second market id for one game. See 499_mo_short_overnight.
# 499_open_vs_off (Finder 2026-11-06, queue item 276, Finder's own, source c): overnight print to the off, racing WIN GB/IE and soccer MO, OU2.5, closed before the off at real prints, nothing held to result. Read only. No tables written. Rule is in the queue, fixed before prices. A far-early print is a last trade, not a touch: a pass here would still need a real early book.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line,step,back_hedge,lay_hedge,tstat
from lib_official import fill,last_in,secs,checks
import lib_cand; lib_cand._checks(); checks()
RB=[(1.5,3,'1.5-3'),(3,6,'3-6'),(6,12,'6-12'),(12,30,'12-30')]
MB=[(1.01,1.5,'<1.5'),(1.5,2,'1.5-2'),(2,3,'2-3'),(3,6,'3-6'),(6,20,'6-20')]
def band(p,B):
    for a,b,n in B:
        if a<=p<b: return n
    return None
assert band(3,RB)=='3-6' and band(30,RB) is None and band(1.2,MB)=='<1.5'
# known answers: back at 3.0 less a tick = 2.98, exit lay at 2.5 plus a tick 2.52: 10*(2.98/2.52-1)=1.8254 less 2%
assert abs(back_hedge(step(3.0,-1),2.5)-10*(2.98/2.52-1)*.98)<1e-9
print("checks: OK",flush=True); T0=time.time()
pd.set_option('display.width',220); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',200)
def trades(P,lo_h,hi_h,bands):
    """P rows of one group. Entry last print in [T-hi_h,T-lo_h], exit last print in [T-300,T-60]. Exit is never earlier than entry by construction."""
    P=P.sort_values('tt',kind='stable').drop_duplicates(['market_id','sel','tt'])
    C=Counter(); rows=[]
    for (m,s),y in P.groupby(['market_id','sel'],sort=False):
        o=float(y.off.iloc[0]); ts,px=y.tt.values,y.ltp.values
        i=last_in(ts,o-hi_h*3600,o-lo_h*3600)
        if i is None: C['no entry print']+=1; continue
        b_=band(float(px[i]),bands)
        if b_ is None: C['outside bands']+=1; continue
        j=last_in(ts,o-300,o-60)
        if j is None: C['no exit print']+=1; continue
        q=float(px[j]); pb,pl=fill(ts,px,i,'B'),fill(ts,px,i,'L'); ab,al=step(pb,-1),step(pl,1)
        vb=None if ab<=1.01 else back_hedge(ab,q); vl=lay_hedge(al,q)
        rows.append((m,y.ty.iloc[0],s,o,b_,vb,vl,q/float(px[i])-1))
    return pd.DataFrame(rows,columns='m ty s off b vb vl mv'.split()),C
def report(D,keys,tag,race=False):
    md=float(np.median(D.off)); out=[]
    for k,x in D.groupby(keys,observed=True):
        k=k if isinstance(k,tuple) else (k,)
        for sd,c in (('back','vb'),('lay','vl')):
            z=x[x[c].notna()]
            if len(z)<30: continue
            l=line(z[c].astype(float).values,np.where(z.off<md,1,2)); tr=tstat(z.groupby('m')[c].sum().astype(float).values)
            p=l['PASS'] and (tr>=3.5 or not race)
            out.append(dict(line=tag+' '+' '.join(map(str,k))+' '+sd,n=l['n'],markets=z.m.nunique(),per10=l['per10'],t=l['t'],t_mkt=tr,n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],mean_move=x.mv.mean(),PASS=p))
    return pd.DataFrame(out)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
# Fixed once 2026-11-06: the one big read ran out of memory, so read and score by month. The rule is unchanged.
MONTHS=list(zip(pd.date_range('2024-01-01','2026-10-01',freq='MS'),pd.date_range('2024-02-01','2026-11-01',freq='MS')))
D1=[];D2=[];D3=[];C1=Counter();C2=Counter();C3=Counter()
for M0,M1 in MONTHS:
    pr_=(M0.to_pydatetime(),M1.to_pydatetime())
    R=pd.read_sql("SELECT market_id,market_type ty,market_time mt,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Horse Racing' AND market_type='WIN' AND country IN ('GB','IE') AND market_time>=%s AND market_time<%s AND NOT inplay AND ltp>=1.01 AND ltp<1000 AND ((ts>=market_time-interval '24 hours' AND ts<=market_time-interval '12 hours') OR (ts>=market_time-interval '5 minutes' AND ts<=market_time-interval '1 minute'))",con,params=pr_)
    if len(R):
        R['tt']=secs(R.ts); R['off']=secs(R.mt); d,c=trades(R,12,24,RB); D1.append(d); C1.update(c)
    del R
    S=pd.read_sql("SELECT market_id,market_type ty,market_time mt,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type IN ('MATCH_ODDS','OVER_UNDER_25') AND market_time>=%s AND market_time<%s AND NOT inplay AND ltp>=1.01 AND ltp<1000 AND ((ts>=market_time-interval '48 hours' AND ts<=market_time-interval '12 hours') OR (ts>=market_time-interval '5 minutes' AND ts<=market_time-interval '1 minute'))",con,params=pr_)
    if len(S):
        S['tt']=secs(S.ts); S['off']=secs(S.mt)
        d,c=trades(S[S.ty=='MATCH_ODDS'],12,48,MB); D2.append(d); C2.update(c)
        d,c=trades(S[S.ty=='OVER_UNDER_25'],12,48,[(1.01,1000,'all')]); D3.append(d); C3.update(c)
    del S
    print(M0.date(),f"{time.time()-T0:.0f}s",flush=True)
con.close()
D1=pd.concat(D1,ignore_index=True); D2=pd.concat(D2,ignore_index=True); D3=pd.concat(D3,ignore_index=True)
print("racing counted:",dict(C1),"trades",len(D1)); print("MO counted:",dict(C2),"trades",len(D2)); print("OU counted:",dict(C3),"trades",len(D3),flush=True)
D3['side']=np.where(D3.s.str.startswith('Over'),'Over','Under')
L1=report(D1,['b'],'RACING',race=True); L2=report(D2,['b'],'MO'); L3=report(D3,['side'],'OU25')
L=pd.concat([L1,L2,L3],ignore_index=True); print(f"\nlines {len(L)}, passing {int(L.PASS.sum())}, a t above 10 is an artefact until shown otherwise")
print(L.sort_values('t',ascending=False).round(3).to_string(index=False))
print("\n== SURVIVORS"); P=L[L.PASS]; print(P.round(3).to_string(index=False) if len(P) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
