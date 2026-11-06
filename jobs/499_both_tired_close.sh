#!/bin/bash
set -o pipefail
# 499_both_tired_close (Finder 2026-11-06, queue item 319, from jobs/499_rematch_close.sh): Over 2.5 when both sides are on short rest, at Pinnacle pre-match odds. Rule pushed before any odds were read. Dates the tape read in item 309 are out. Read only. A proxy, so no line can pass the bar.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(1_500_000_000,1_500_000_000))
import sys,time,datetime as dt,psycopg2,pandas as pd,numpy as np
from collections import defaultdict,Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,line,back_settle,lay_settle
pd.set_option('display.width',240); pd.set_option('display.max_columns',30)
def band(p): return '<1.7' if p<1.7 else '1.7-2.1' if p<2.1 else '2.1+'
def ly(x,won): return lay_settle(step(x,1),won)
def state(a,b):
    if a is None or b is None: return None
    return 'BOTH' if a<=3 and b<=3 else 'CTRL' if 5<=a<=10 and 5<=b<=10 else None
def rest_days(ds,d):
    p=None
    for x in ds:
        if x<d: p=x
        else: break
    if p is None or (d-p).days>14: return None
    return (d-p).days
def fair3(a,b,c): s=1/a+1/b+1/c; return (1/a)/s,(1/b)/s,(1/c)/s
def bk(x,won):
    a=step(x,-1); return np.nan if a<=1.01 else back_settle(a,won)
def outside(d): return not (dt.date(2024,1,1)<=d<=dt.date(2024,10,31) or dt.date(2026,5,1)<=d<=dt.date(2026,9,30))
def pooled_z(a,ab,c,cb):
    """err arrays a (rematch) and c (control) with bands. Difference within band, weighted by rematch n. Returns (diff, z)."""
    a,ab,c,cb=map(np.asarray,(a,ab,c,cb)); W=D=V=0.0
    for b in np.unique(ab):
        x,y=a[ab==b],c[cb==b]
        if len(x)<2 or len(y)<2: continue
        w=len(x); W+=w; D+=w*(x.mean()-y.mean()); V+=w*w*(x.var(ddof=1)/len(x)+y.var(ddof=1)/len(y))
    return D/W,(D/W)/((V**0.5)/W)
# known answers, worked by hand
assert band(1.69)=='<1.7' and band(1.7)=='1.7-2.1' and band(2.1)=='2.1+'
assert state(3,3)=='BOTH' and state(3,4) is None and state(5,10)=='CTRL' and state(4,5) is None and state(None,3) is None
D_=dt.date; assert rest_days([D_(2025,1,1),D_(2025,1,4)],D_(2025,1,7))==3 and rest_days([D_(2025,1,1)],D_(2025,2,1)) is None and rest_days([],D_(2025,1,1)) is None and rest_days([D_(2025,1,1),D_(2025,1,4)],D_(2025,1,4))==3
assert abs(ly(2.0,False)-10/1.02*.98)<1e-9 and ly(2.0,True)==-10.0
f=fair3(2.0,4.0,4.0); assert abs(f[0]-0.5)<1e-9 and abs(f[1]-0.25)<1e-9
assert abs(bk(2.0,True)-10*.99*.98)<1e-9 and bk(2.0,False)==-10.0
assert outside(dt.date(2023,12,31)) and not outside(dt.date(2024,1,1)) and outside(dt.date(2024,11,1)) and not outside(dt.date(2026,9,30)) and outside(dt.date(2026,10,1))
d_,z_=pooled_z([1.,3.],['a','a'],[0.,2.],['a','a']); assert abs(d_-1.0)<1e-9 and abs(z_-1.0/((2/2+2/2)**0.5))<1e-9
print("known-answer checks: OK",flush=True); T0=time.time()
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
c=psycopg2.connect(creds.pg_local()); F=pd.read_sql("SELECT div,date,home,away,fthg::int fthg,ftag::int ftag,p_o25::float8 po,p_u25::float8 pu FROM fd_matches WHERE fthg IS NOT NULL AND ftag IS NOT NULL",c); c.close()
print("games",len(F),F.date.min(),F.date.max(),flush=True)
DS=defaultdict(set)
for r in F.itertuples(): DS[r.home].add(r.date); DS[r.away].add(r.date)
DS={k:sorted(v) for k,v in DS.items()}
C=Counter(); rows=[]
import bisect
def rest_fast(ds,d):
    i=bisect.bisect_left(ds,d)-1
    if i<0 or (d-ds[i]).days>14: return None
    return (d-ds[i]).days
assert rest_fast([D_(2025,1,1),D_(2025,1,4)],D_(2025,1,7))==rest_days([D_(2025,1,1),D_(2025,1,4)],D_(2025,1,7))==3
for r in F.itertuples():
    if not (r.po>1 and r.pu>1): C['no odds']+=1; continue
    if not outside(r.date): C['tape dates, out']+=1; continue
    st=state(rest_fast(DS[r.home],r.date),rest_fast(DS[r.away],r.date))
    if st is None: C['no state']+=1; continue
    won=r.fthg+r.ftag>=3; fo=(1/r.po)/(1/r.po+1/r.pu)
    rows.append((st,band(r.po),pd.Timestamp(r.date),r.po,won,float(won)-fo,ly(r.po,won),r.div))
A=pd.DataFrame(rows,columns='st band d px won err vl div'.split()); A['won']=A.won.astype(bool)
print("counts",dict(C),"labels",A.st.value_counts().to_dict(),"BOTH by div",A[A.st=='BOTH']['div'].value_counts().head(10).to_dict(),f"by year {A[A.st=='BOTH'].d.dt.year.value_counts().sort_index().to_dict()}",flush=True)
L=A[A.st=='BOTH']; K=A[A.st=='CTRL']; dd,z=pooled_z(L.err,L.band,K.err,K.band); z=-z
x=L[L.vl.notna()]; l=line(x.vl.values,np.where(x.d<x.d.median(),1,2))
print(f"\n== TEST: BOTH n {len(L)} won {L.won.mean():.3f} implied {(1/L.px).mean():.3f}; err minus control within band {dd:+.4f}; z downward {z:.2f}: {'SUPPORTED' if z>=2 else 'NOT SUPPORTED'}")
print(f"  lay Over at the price, one tick, 2%: n {l['n']} {l['per10']:+.3f} t {l['t']:.2f} h1 {l['h1']:+.3f} h2 {l['h2']:+.3f}; control lay {K.vl.mean():+.3f}",flush=True)
print("\n== context, not tests")
for b in ('<1.7','1.7-2.1','2.1+'):
    y=L[L.band==b]; k=K[K.band==b]
    if len(y)>1: print(f"  BOTH {b}: n {len(y)} err {y.err.mean():+.4f} v control {k.err.mean():+.4f}")
print("\n== SURVIVORS: none can pass at this proxy; re-check on unseen tape months only if the z test is supported"); print(f"total {time.time()-T0:.0f}s")
PY
