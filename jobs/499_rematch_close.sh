#!/bin/bash
set -o pipefail
# 499_rematch_close (Finder 2026-11-06, queue item 318, from jobs/499_second_leg_check.sh): the loser of a game, in the reversed fixture 3 to 21 days later, at Pinnacle closes. Rule pushed before any close was read. Dates the tape read in item 310 are out: Jan-Oct 2024 and May-Sep 2026. Read only. Closes are a proxy, so no line can pass the bar: support earns a forward test.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(1_500_000_000,1_500_000_000))
import sys,time,datetime as dt,psycopg2,pandas as pd,numpy as np
from collections import defaultdict,Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,line,back_settle
pd.set_option('display.width',240); pd.set_option('display.max_columns',30)
def band(p): return '<2' if p<2 else '2-3' if p<3 else '3-5' if p<5 else '5+'
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
assert band(1.99)=='<2' and band(2.0)=='2-3' and band(3.0)=='3-5' and band(5.0)=='5+'
f=fair3(2.0,4.0,4.0); assert abs(f[0]-0.5)<1e-9 and abs(f[1]-0.25)<1e-9
assert abs(bk(2.0,True)-10*.99*.98)<1e-9 and bk(2.0,False)==-10.0
assert outside(dt.date(2023,12,31)) and not outside(dt.date(2024,1,1)) and outside(dt.date(2024,11,1)) and not outside(dt.date(2026,9,30)) and outside(dt.date(2026,10,1))
d_,z_=pooled_z([1.,3.],['a','a'],[0.,2.],['a','a']); assert abs(d_-1.0)<1e-9 and abs(z_-1.0/((2/2+2/2)**0.5))<1e-9
print("known-answer checks: OK",flush=True); T0=time.time()
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
c=psycopg2.connect(creds.pg_local()); F=pd.read_sql("SELECT div,date,home,away,fthg::int fthg,ftag::int ftag,psch::float8 psch,pscd::float8 pscd,psca::float8 psca FROM fd_matches WHERE fthg IS NOT NULL AND ftag IS NOT NULL",c); c.close()
F['d']=pd.to_datetime(F.date); print("games",len(F),F.date.min(),F.date.max(),flush=True)
LOST=defaultdict(list)
for r in F.itertuples():
    if r.fthg!=r.ftag: LOST[(r.div,r.home,r.away)].append((r.d,r.home if r.fthg<r.ftag else r.away))   # who lost at home v away
C=Counter(); rows=[]
for r in F.itertuples():
    if not (r.psch>1 and r.pscd>1 and r.psca>1): C['no closes']+=1; continue
    if not outside(r.date): C['tape dates, out']+=1; continue
    fh,fd,fa=fair3(r.psch,r.pscd,r.psca); lo=None
    for d0,who in LOST.get((r.div,r.away,r.home),[]):
        if 3<=(r.d-d0).days<=21: lo=who
    hw,aw=r.fthg>r.ftag,r.ftag>r.fthg
    for team,p,fr,won,home in ((r.home,r.psch,fh,hw,True),(r.away,r.psca,fa,aw,False)):
        rows.append(('LOSER' if team==lo else 'WINNER' if lo else 'CTRL',band(p),r.d,p,won,float(won)-fr,bk(p,won),home,r.div))
A=pd.DataFrame(rows,columns='st band d px won err vb home div'.split()); A['won']=A.won.astype(bool)
print("counts",dict(C),"labels",A.st.value_counts().to_dict(),"LOSER by div",A[A.st=='LOSER']['div'].value_counts().head(12).to_dict(),f"by year {A[A.st=='LOSER'].d.dt.year.value_counts().sort_index().to_dict()}",flush=True)
L=A[A.st=='LOSER']; K=A[A.st=='CTRL']; dd,z=pooled_z(L.err,L.band,K.err,K.band)
x=L[L.vb.notna()]; hh=np.where(x.d<x.d.median(),1,2); l=line(x.vb.values,hh)
print(f"\n== TEST: LOSER n {len(L)} won {L.won.mean():.3f} implied {(1/L.px).mean():.3f}; err minus control within band {dd:+.4f}; z {z:.2f}: {'SUPPORTED' if z>=2 else 'NOT SUPPORTED'}")
print(f"  back at the close, one tick, 2%: n {l['n']} {l['per10']:+.3f} t {l['t']:.2f} h1 {l['h1']:+.3f} h2 {l['h2']:+.3f}",flush=True)
print("\n== context, not tests")
for lab,m in (('at home',L.home),('away',~L.home)):
    y=L[m]; d2,z2=pooled_z(y.err,y.band,K.err,K.band); print(f"  LOSER {lab}: n {len(y)} won {y.won.mean():.3f} implied {(1/y.px).mean():.3f}; diff {d2:+.4f} z {z2:.2f}")
for b in ('<2','2-3','3-5','5+'):
    y=L[L.band==b]; k=K[K.band==b]
    if len(y)>1: print(f"  LOSER {b}: n {len(y)} err {y.err.mean():+.4f} v control {k.err.mean():+.4f}")
W=A[A.st=='WINNER']; d3,z3=pooled_z(W.err,W.band,K.err,K.band); print(f"  WINNER of the first game: n {len(W)} diff {d3:+.4f} z {z3:.2f}")
print("\n== SURVIVORS: none can pass at closes; forward test only if the z test is supported"); print(f"total {time.time()-T0:.0f}s")
PY
