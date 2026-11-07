#!/bin/bash
set -o pipefail
# STRUCK 2026-11-07: 90% of these reopens are replayed book states, see reports/finder_2026-11-07_items265-402.md. Its numbers are not a read of any market.
# 499_reopen_racing (Finder 2026-11-07, queue item 396, Finder's own, source d; first Finder read of ip_reopen): racing, the runner the first in-play book moves most, at the real touch, held to the result. Rule pushed in the queue before any price. Read only, no tables written. Both tables are live tape on Railway.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(1_500_000_000,1_500_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
import lib_cand
from lib_cand import line,step,back_settle,lay_settle
from lib_official import bk,ly,secs,checks
lib_cand._checks(); checks()
def real(b,l): return b==b and l==l and b>1.0 and l<=b*1.05
def pick(rows):
    """rows: (id, move). (short id, drift id, flat id), each None if no runner qualifies. Lowest move at -15% or beyond, highest at +15% or beyond, smallest absolute under 5%."""
    if not rows: return None,None,None
    lo=min(rows,key=lambda z:z[1]); hi=max(rows,key=lambda z:z[1]); fl=min(rows,key=lambda z:abs(z[1]))
    return (lo[0] if lo[1]<=-0.15 else None),(hi[0] if hi[1]>=0.15 else None),(fl[0] if abs(fl[1])<0.05 else None)
# known answers, worked by hand
assert real(2.0,2.1) and not real(2.0,2.11) and not real(float('nan'),2.0) and not real(1.01,29.0)
assert pick([('a',-.2),('b',.3),('c',.01)])==('a','b','c') and pick([('a',-.1),('b',.1)])==(None,None,None) and pick([])==(None,None,None) and pick([('a',-.15),('b',.15)])==('a','b',None)
assert abs(bk(4.0,True)-(3.95-1)*10*.98)<1e-9 and bk(4.0,False)==-10.0 and abs(ly(4.9,False)-2.45)<1e-9 and ly(4.9,True)==-10.0
print("checks: OK",flush=True); T0=time.time()
pd.set_option('display.width',220); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',60)
rc=psycopg2.connect(creds.pg_railway(),sslmode='require'); rc.autocommit=True; rc.cursor().execute("SET statement_timeout='300s'")
Q="sport IN ('horse_racing','racing') AND market_type='WIN'"
R=pd.read_sql("SELECT r.ts,r.market_id,r.event_name,r.secs_since_start ss,r.suspended_secs su,r.sel_id,r.pre_ltp::float8 pre,r.post_back_px::float8 b,r.post_lay_px::float8 l FROM ip_reopen r JOIN (SELECT market_id,min(ts) t0 FROM ip_reopen WHERE "+Q+" GROUP BY 1) f ON r.market_id=f.market_id AND r.ts=f.t0 WHERE r.market_type='WIN'",rc)
W=pd.read_sql("SELECT market_id,selection_id sel_id,won,bsp::float8 bsp FROM racing_results WHERE market_id=ANY(%s)",rc,params=(list(R.market_id.unique()),)); rc.close()
print(f"first-reopen rows {len(R):,}, markets {R.market_id.nunique():,}; result rows {len(W):,}, markets {W.market_id.nunique():,}; {time.time()-T0:.0f}s",flush=True)
wc=W.assign(w=W.won.eq(True)).groupby('market_id').w.sum(); ok=set(wc[wc==1].index); print("markets with one winner",len(ok),"of",W.market_id.nunique(),flush=True)
D=R.merge(W,on=['market_id','sel_id'],how='left'); C=Counter(); C['reopen markets, no result, overseas or later']=int(R.market_id.nunique()-R[R.market_id.isin(ok)].market_id.nunique())
D=D[D.market_id.isin(ok)]
# audit: is the first reopen the off? pre_ltp should sit near BSP, seconds should be early
A=D[D.pre.notna()&D.bsp.notna()&(D.bsp<30)]
print("AUDIT first reopen, secs after scheduled start p10 p50 p90",D.drop_duplicates('market_id').ss.quantile([.1,.5,.9]).round(0).tolist(),"; median abs pre_ltp/BSP-1 under BSP 30",round(float((A.pre/A.bsp-1).abs().median()),3),"share winner on row",round(float(D.assign(w=D.won.eq(True)).groupby('market_id').w.max().mean()),3),flush=True)
rows=[]
for m,g in D.groupby('market_id',sort=True):
    o=float(secs(g.ts.iloc[[0]]).iloc[0]); cand=[]; info={}
    for r in g.itertuples():
        if r.won is None or r.won!=r.won: C['runner with no result']+=1; continue
        if not (r.pre==r.pre and r.pre>1.0): C['runner no pre_ltp']+=1; continue
        if not real(r.b,r.l): C['runner no real book']+=1; continue
        mv=0.5*(r.b+r.l)/r.pre-1; cand.append((r.sel_id,mv)); info[r.sel_id]=(r.b,r.l,bool(r.won),r.pre,mv)
    s,d_,f=pick(cand)
    for st,x in (('SHORT',s),('DRIFT',d_),('FLAT',f)):
        if x is None: C[st+' none in race']+=1; continue
        b,l,won,pre,mv=info[x]
        vb=bk(b,won); vl=ly(l,won)
        vb3=bk(step(b,-2),won); vl3=ly(step(l,2),won)
        rows.append((st,m,o,b,l,won,pre,mv,vb,vl,vb3,vl3))
print("counted:",dict(sorted(C.items())),flush=True)
T=pd.DataFrame(rows,columns='st m off b l won pre mv vb vl vb3 vl3'.split()); assert not T.duplicated(['st','m']).any(); md=float(np.median(T.drop_duplicates('m').off))
print("races",T.m.nunique(),"split at",pd.Timestamp(md,unit='s',tz='UTC'),flush=True)
out=[]
def rd(nm,x,c,imp,scored):
    z=x[x[c].notna()]
    if len(z)<2: return
    l=line(z[c].astype(float).values,np.where(z.off<md,1,2)); out.append(dict(line=nm,n=l['n'],per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],maxwin=l['maxwin'],won=z.won.astype(float).mean(),imp=(1/z[imp]).mean(),PASS=bool(l['PASS'] and scored)))
for st in ('SHORT','DRIFT','FLAT'):
    x=T[T.st==st]; sc=st!='FLAT'
    rd(f'{st} back',x,'vb','b',sc); rd(f'{st} lay',x,'vl','l',sc); rd(f'{st} back 3 ticks, stress',x,'vb3','b',False); rd(f'{st} lay 3 ticks, stress',x,'vl3','l',False)
O=pd.DataFrame(out); print("\n"+O.sort_values('t',ascending=False).round(3).to_string(index=False))
print("\nby entry price, context, cannot pass")
T['band']=pd.cut(T.b,[1,3,6,12,30,1000],right=False)
for st,side,c in (('SHORT','back','vb'),('SHORT','lay','vl'),('DRIFT','back','vb'),('DRIFT','lay','vl')):
    x=T[(T.st==st)&T[c].notna()]; print(st,side,x.groupby('band',observed=True).agg(n=(c,'size'),per10=(c,lambda s:s.astype(float).mean()),won=('won',lambda s:s.astype(float).mean()),imp=('b',lambda s:(1/s).mean())).round(3).to_dict('index'))
S=O[O.PASS==True]; print(f"\n== SURVIVORS: {len(S)} of 4\n",S.round(3).to_string(index=False) if len(S) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
