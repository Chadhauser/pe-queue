#!/bin/bash
set -o pipefail
# 499_jump_up_ou25 (Finder 2026-11-08, queue item 444, Finder's own, source a, from item 414): jobs/499_jump_up_back.sh unchanged except the market. OVER_UNDER_25, Over and Under 2.5 Goals: back a runner whose first in-play print sits 2 to under 4 implied points over its last pre-off print. MO chose the rule; OU25 has never been read with it, so this can pass. Rule pushed in the queue before this job read an OU price. Read only, no tables written. Prints only, so a pass is an upper bound and earns a touch read, not a stake. The liq_sample touch section of 414 is left out tonight (time); a pass earns it.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line,step,back_settle
from lib_official import bk,fill,last_in,first_in,secs,checks,group,load_results
import lib_cand; lib_cand._checks(); checks()
pd.set_option('display.width',220); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',200)
SELS={'Over 2.5 Goals':'OVER','Under 2.5 Goals':'UNDER'}
def gap_pts(pre,ip): return 100*(1/pre-1/ip)
def state(g):
    """g points: UP24, UP12, DN24, or None. As item 414."""
    a=abs(g)
    if 2<=a<4: return 'UP24' if g>0 else 'DN24'
    if 1<=a<2 and g>0: return 'UP12'
    return None
def bk3(x,won):
    a=step(x,-3); return None if a<=1.01 else back_settle(a,won)
def next_only(ts,px,i,nxt=120):
    return float(px[i+1]) if i+1<len(ts) and ts[i+1]-ts[i]<=nxt else None
# known answers, worked by hand (as item 414)
assert abs(gap_pts(2.0,2.1)-2.38095)<1e-4 and state(gap_pts(2.0,2.1))=='UP24'
assert state(gap_pts(2.0,1.9))=='DN24' and state(gap_pts(2.0,2.06))=='UP12' and state(gap_pts(2.0,1.95)) is None and state(gap_pts(2.0,2.5)) is None
assert state(2.0)=='UP24' and state(3.999)=='UP24' and state(4.0) is None and state(1.0)=='UP12' and state(0.99) is None
assert abs(bk3(2.06,True)-9.8)<1e-9 and bk3(2.06,False)==-10.0 and bk3(1.03,True) is None
assert abs(bk(2.04,True)-9.996)<1e-9 and bk(2.04,False)==-10.0
assert fill(np.array([0.,60.]),np.array([2.1,2.0]),0,'B')==2.0 and fill(np.array([0.,200.]),np.array([2.1,2.0]),0,'B')==2.1   # worse of print and next within 120 s; 200 s later is not used
print("checks: OK",flush=True); T0=time.time()
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
RS,dr=load_results(con,['OVER_UNDER_25']); print("official OU25 markets",len(RS),"dropped",dr,f"{time.time()-T0:.0f}s",flush=True)
C=Counter(); rows=[]
def month_chunks():
    for y,ms in ((2023,range(4,13)),(2024,range(1,12)),(2026,range(5,11))):
        for m in ms:
            a=pd.Timestamp(y,m,1); e=a+pd.offsets.MonthBegin(1)
            if (y,m)>=(2026,8):
                while a<e:
                    b=min(a+pd.Timedelta(days=5),e); yield str(a.date()),str(b.date()); a=b
            else: yield str(a.date()),str(e.date())
for lo,hi in month_chunks():
    X=pd.read_sql("SELECT market_id,event_name ev,market_time mt,sel,inplay,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type='OVER_UNDER_25' AND sel=ANY(%s) AND ltp>=1.01 AND ltp<1000 AND ts>=market_time-interval '11 minutes' AND ts<=market_time+interval '6 minutes' AND market_time>=%s AND market_time<%s",con,params=(list(SELS),lo,hi))
    if X.empty: print(lo,"no rows",flush=True); continue
    X['tt']=secs(X.ts); X['off']=secs(X.mt); X=X.sort_values('tt',kind='stable').drop_duplicates(['market_id','sel','tt'])
    for (ev,off),G_ in X.groupby(['ev','off'],sort=False):
        ids=sorted(G_.market_id.unique()); mk=ids[0]
        if len(ids)>1: C['two OU25 markets, first kept']+=1
        if ' v ' not in ev: C['no H v A']+=1; continue
        if group(ev): C['women or youth']+=1; continue
        if mk not in RS: C['no official']+=1; continue
        g0=G_[G_.market_id==mk]
        for s,y in g0.groupby('sel',sort=False):
            if s not in RS[mk]: C['sel not in result']+=1; continue
            pm=y[~y.inplay]; ip=y[y.inplay]
            a,b,c,d=pm.tt.values,pm.ltp.values,ip.tt.values,ip.ltp.values
            i=first_in(c,off-300,off+180)
            if i is None: C['no first print']+=1; continue
            pre=last_in(a,off-600,float(c[i]))
            if pre is None: C['no pre print']+=1; continue
            g=gap_pts(float(b[pre]),float(d[i])); st=state(g)
            if st is None: continue
            rows.append(dict(st=st,r=SELS[s],ev=ev,off=off,g=abs(g),px=float(d[i]),pb=fill(c,d,i,'B'),nx=next_only(c,d,i),won=RS[mk][s],age=float(c[i]-a[pre]),delay=float(c[i]-off)))
    print(lo,"rows",len(X),"cands",len(rows),f"{time.time()-T0:.0f}s",flush=True); del X
con.close(); print("counts",dict(sorted(C.items())),flush=True)
T=pd.DataFrame(rows); T=T[T.pb<=50].copy()
med=T.off.median(); T['h']=np.where(T.off<=med,1,2)
def row(nm,x,col='vb'):
    x=x.dropna(subset=[col]); v=x[col].astype(float).values
    if len(v)<2: return dict(line=nm,n=len(v))
    d=line(v,x.h.values); gm=x[['ev','off']].drop_duplicates().shape[0]
    return dict(line=nm,n=d['n'],games=gm,per10=round(d['per10'],3),t=round(d['t'],2),h1=round(d['h1'],3),h2=round(d['h2'],3),n1=d['n1'],n2=d['n2'],no_top=round(np.delete(v,v.argmax()).mean(),3),won=round(x.won.astype(float).mean(),3),imp=round((1/x.px).mean(),3),PASS=d['PASS'])
T['vb']=[bk(p,w) for p,w in zip(T.pb,T.won)]
T['v3']=[bk3(p,w) for p,w in zip(T.pb,T.won)]
T['vn']=[None if n is None or n!=n or n>50 else bk(n,w) for n,w in zip(T.nx,T.won)]
U=T[T.st=='UP24'].copy()
ONE=U.sort_values(['g','r'],ascending=[False,True]).drop_duplicates(['ev','off']).sort_values('off')   # one bet per game, the larger gap
print(f"\n== ITEM 444, scored ONE E1; halves split at {pd.to_datetime(med,unit='s')}; pre-print age median {ONE.age.median():.0f}s, first print median {ONE.delay.median():.0f}s after market time")
o=[row('ONE E1 worse of print and next *',ONE),row('ONE E2 next print only',ONE,'vn'),row('ONE E3 worse, 3 ticks',ONE,'v3')]
for r_ in ('OVER','UNDER'): o.append(row(f'{r_} E1',ONE[ONE.r==r_]))
for y in (2023,2024,2026): o.append(row(f'ONE year {y} E1',ONE[pd.to_datetime(ONE.off,unit='s').dt.year==y]))
for lab,a,b in (('px<1.8',0,1.8),('px 1.8-2.5',1.8,2.5),('px 2.5-50',2.5,51)): o.append(row(f'ONE {lab} E1',ONE[(ONE.px>=a)&(ONE.px<b)]))
print(pd.DataFrame(o).to_string(index=False))
c=[]
for st,lab in (('UP12','CONTROL UP 1-2 back'),('DN24','CONTROL DOWN 2-4 back')):
    x=T[T.st==st].sort_values('g',ascending=False).drop_duplicates(['ev','off']); c+=[row(lab+' E1',x)]
    for r_ in ('OVER','UNDER'): c.append(row(f'{lab} {r_} E1',x[x.r==r_]))
print("\n-- controls, one bet per game, not scored\n",pd.DataFrame(c).to_string(index=False),flush=True)
S=row('ONE E1',ONE); print("\n== SURVIVORS"); print(S if S.get('PASS') else "none",flush=True); print(f"total {time.time()-T0:.0f}s")
PY
