#!/bin/bash
set -o pipefail
# 499_ip_touch_level (Finder 2026-11-07, queue item 379, Finder's own, source a, from item 372): a horse's first in-play touch of a price level, entered at the real touch after a delay. Rule pushed before any price was scored. Read only. Replay frames dropped as jobs/497.
# ENTRY first clean frame with back_px <= Q after a clean frame with back_px > Q; fill at the first clean frame at least 2 s later with a touch on that side, one tick adverse. No later frame, no trade, counted. Result racing_results, one winner only; races with none not scored, counted. 2%, £10 risk.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(1_500_000_000,1_500_000_000))  # this job only
import sys,time,psycopg2,warnings,pandas as pd,numpy as np
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,back_settle,lay_settle,tstat,passes
from lib_wom import tgame
pd.set_option('display.width',230); pd.set_option('display.max_rows',120); pd.set_option('display.max_columns',30)
T0=time.time(); DELAY=2.0
def clean_mask(tm):
    """A frame is a replay if its total matched is below the running max of earlier frames. NaN kept, does not move the max."""
    tm=np.asarray(tm,float); ok=np.ones(len(tm),bool); m=-np.inf
    for i,x in enumerate(tm):
        if x==x:
            if x<m: ok[i]=False
            else: m=x
    return ok
def first_touch(t,bp,lp,q,delay=DELAY):
    """t seconds, bp, lp arrays for one runner, clean frames. (entry index for a back, entry index for a lay, start price) or None. nan = no touch that frame."""
    v=np.where(bp==bp)[0]
    if len(v)<2: return None
    if bp[v[0]]<=q: return None      # already at or under Q at the first frame: no cross seen
    h=v[bp[v]<=q]
    if not len(h): return None
    i=h[0]; ib=il=None
    for j in range(i+1,len(t)):
        if t[j]>=t[i]+delay:
            if ib is None and bp[j]==bp[j]: ib=j
            if il is None and lp[j]==lp[j]: il=j
            if ib is not None and il is not None: break
    return ib,il,bp[v[0]]
def bk(p,w):
    a=step(p,-1); return np.nan if a<=1.01 else back_settle(a,w)
def ly(p,w): return lay_settle(step(p,1),w)
# known answers, worked by hand
assert clean_mask([10,12,11,12,13,12.5]).tolist()==[True,True,False,True,True,False] and clean_mask([10,float('nan'),9,11]).tolist()==[True,True,False,True]
n_=np.nan
_t=np.array([0.,1,2,3,4,6]); _b=np.array([3.0,2.5,2.0,1.9,1.8,1.7]); _l=np.array([3.1,2.6,2.1,n_,1.9,1.8])
assert first_touch(_t,_b,_l,2.0)==(4,4,3.0)          # touched at frame 2, t=2; first frame at t>=4 is index 4
assert first_touch(_t,_b,_l,1.0) is None and first_touch(_t,_b,_l,3.0) is None      # never touched; already there at the first frame
assert first_touch(np.array([0.,1,2]),np.array([3.0,2.0,1.9]),np.array([3.1,2.1,2.0]),2.0)==(None,None,3.0)    # no frame 2 s later
assert abs(bk(2.0,True)-10*.99*.98)<1e-9 and ly(2.0,True)==-10.0 and abs(ly(2.0,False)-10/1.02*.98)<1e-9 and np.isnan(bk(1.02,True))
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
cur.execute("""SELECT market_id,extract(epoch from ts)::float8,sel_id,back_px::float8,lay_px::float8,total_matched::float8 FROM ip_tape WHERE sport='horse_racing' AND market_type='WIN' AND status='OPEN' AND secs_since_start>0""")
A=pd.DataFrame(cur.fetchall(),columns='market_id t sel bp lp tm'.split()); con.close(); print(f"rows {len(A):,}, markets {A.market_id.nunique()}, {pd.to_datetime(A.t.min(),unit='s')} to {pd.to_datetime(A.t.max(),unit='s')}, {time.time()-T0:.0f}s",flush=True)
rc=psycopg2.connect(creds.pg_railway(),sslmode='require'); k=rc.cursor(); k.execute("SET statement_timeout='300s'"); k.execute("SELECT market_id,selection_id FROM racing_results WHERE won AND market_id=ANY(%s)",(list(A.market_id.unique()),)); W={}
for m,s in k.fetchall(): W.setdefault(m,[]).append(int(s))
rc.close(); truth={m:v[0] for m,v in W.items() if len(v)==1}; print(f"markets on tape {A.market_id.nunique()}, one winner {len(truth)}, dead heats {sum(len(v)>1 for v in W.values())}",flush=True)
A=A[A.market_id.isin(truth)].sort_values(['market_id','t'],kind='stable')
F=A.groupby(['market_id','t'],sort=False).tm.max().reset_index(); F['ok']=np.concatenate([clean_mask(g.tm.values) for _,g in F.groupby('market_id',sort=False)]); A=A.merge(F[['market_id','t','ok']],on=['market_id','t']); print(f"rows in replay frames {(~A.ok).mean():.1%}",flush=True); A=A[A.ok]
gaps=F[F.ok].groupby('market_id').t.diff().dropna(); print(f"seconds between clean frames: median {gaps.median():.1f}, p90 {gaps.quantile(.9):.1f}, p99 {gaps.quantile(.99):.1f}",flush=True)
rows=[]; nofill=0
for (m,s),x in A.groupby(['market_id','sel'],sort=False):
    t,b,l=x.t.values,x.bp.values,x.lp.values; won=truth[m]==int(s)
    for q in (3,2,1.5,1.3,1.2,1.1):
        r=first_touch(t,b,l,q)
        if r is None: continue
        ib,il,st=r; mv=st>=1.5*q
        if ib is None and il is None: nofill+=1
        if ib is not None:
            v=bk(b[ib],won)
            if v==v: rows.append((m,t[ib],q,'back',b[ib],won,v,mv))
        if il is not None: rows.append((m,t[il],q,'lay',l[il],won,ly(l[il],won),mv))
R=pd.DataFrame(rows,columns='m t q side px won v mv'.split()); print(f"entries {len(R):,}; touched with no frame 2 s later {nofill}",flush=True)
def tab(x,**k):
    v=x.v.values; md=np.median(x.t.values); h=x.t.values<md; a,b=v[h],v[~h]; tr=tgame(v,x.m.values)
    return dict(**k,n=len(v),races=x.m.nunique(),per10=v.mean(),t=tstat(v),tr=tr,n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,won=x.won.mean(),fill=x.px.mean(),imp=(1/x.px).mean(),maxwin=v.max(),PASS=passes(len(v),len(a),len(b),tr,a.mean() if len(a) else 0,b.mean() if len(b) else 0,v.mean()))
out=[]
for (q,s),x in R.groupby(['q','side']):
    out.append(tab(x,q=q,side=s,start='ALL')); y=x[x.mv]
    if len(y)>=30: out.append(tab(y,q=q,side=s,start='MOVE'))
O=pd.DataFrame(out).sort_values('tr',ascending=False); print(f"\n== ITEM 379: {len(O)} lines, by t per race\n",O.round(3).to_string(index=False))
Z=O[O.PASS==True]; print(f"\n== SURVIVORS: {len(Z)}\n",Z.round(3).to_string(index=False) if len(Z) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
