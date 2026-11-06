#!/bin/bash
set -o pipefail
# 499_flow_closed (Finder 2026-11-06, queue item 298, Finder's own, source b; from jobs/499_flip_flow.sh): signed prints before the off, in at the end of the flow window, out before the off, four sports. Rule pushed in the queue before any price. Read only, no tables written. Prints only, so a pass is an upper bound. No result is read.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line,step,back_hedge,lay_hedge
from lib_official import fill,last_in,first_in,secs,checks
import lib_cand; lib_cand._checks(); checks()
pd.set_option('display.width',220); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',200)
def flow(px):
    d=u=0; l=None
    for p in px:
        if l is not None and p!=l:
            if p<l: d+=1
            else: u+=1
        l=p
    n=d+u
    return n,(d-u)/n if n else 0.0
def exit_price(tt,lp,off):
    """Last print T-5 to T-2; else first print after T-2 to the off, counted; else None. Prints passed are pre-off only."""
    j=last_in(tt,off-300,off-120)
    if j is not None: return float(lp[j]),'WINDOW'
    j=first_in(tt,off-120+1e-6,off)
    return (float(lp[j]),'LATE') if j is not None else (None,'NONE')
def trades(state,B,L,q):
    """Back price B and lay price L are worse-of fills before the tick. Returns [(label,pnl)]; BUY follow backs, SELL follow lays."""
    a=step(B,-1); vb=None if a<=1.01 else back_hedge(a,q); vl=lay_hedge(step(L,1),q)
    out=[]
    if state=='BUY': out=[('BUY follow',vb),('BUY fade',vl)]
    if state=='SELL': out=[('SELL follow',vl),('SELL fade',vb)]
    return [(l,v) for l,v in out if v is not None]
assert flow([2.0,1.9,1.9,1.8,1.9,1.7])==(4,0.5)
_t=np.array([-600.,-200.,-150.,-60.]); _p=np.array([2.,2.1,2.2,2.3])
assert exit_price(_t,_p,0.)==(2.2,'WINDOW') and exit_price(_t[[0,3]],_p[[0,3]],0.)==(2.3,'LATE') and exit_price(_t[:1],_p[:1],0.)==(None,'NONE')
_x=dict(trades('BUY',2.0,2.0,2.0)); assert abs(_x['BUY follow']-back_hedge(1.99,2.0))<1e-9 and abs(_x['BUY fade']-lay_hedge(2.02,2.0))<1e-9
_y=dict(trades('SELL',2.0,2.0,2.0)); assert abs(_y['SELL follow']-lay_hedge(2.02,2.0))<1e-9 and abs(_y['SELL fade']-back_hedge(1.99,2.0))<1e-9
print("checks: OK",flush=True); T0=time.time()
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
SP=[('Horse Racing','WIN',1200,600,660,('GB','IE'),'2024-09-01','2026-10-01'),
    ('Greyhound Racing','WIN',1200,600,660,('GB','IE'),'2024-09-01','2026-10-12'),
    ('Tennis','MATCH_ODDS',3600,1200,1320,None,'2024-09-01','2026-04-02'),
    ('Cricket','MATCH_ODDS',3600,1200,1320,None,'2024-09-01','2026-10-01')]
rows=[]; C=Counter()
for sp,ty,fl,en,elo,ctry,a,b in SP:
    d0=pd.Timestamp(a); e=pd.Timestamp(b)
    while d0<e:
        d1=min(d0+pd.Timedelta(days=15),e)
        q="SELECT market_id,market_time mt,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport=%s AND market_type=%s AND NOT inplay AND ltp>=1.01 AND ltp<1000 AND ts>=market_time-make_interval(secs=>%s) AND ts<=market_time AND market_time>=%s AND market_time<%s"
        pa=[sp,ty,fl,str(d0.date()),str(d1.date())]
        if ctry: q+=" AND country=ANY(%s)"; pa.append(list(ctry))
        X=pd.read_sql(q,con,params=tuple(pa))
        if len(X):
            X['tt']=secs(X.ts); X['off']=secs(X.mt); X=X.sort_values('tt',kind='stable').drop_duplicates(['market_id','sel','tt'])
            for (mk,off),G_ in X.groupby(['market_id','off'],sort=False):
                C[sp+' markets']+=1; best={}
                for s,y in G_.groupby('sel',sort=False):
                    tt,lp=y.tt.values,y.ltp.values
                    m=(tt>=off-fl)&(tt<=off-en)
                    if m.sum()<2: continue
                    n,im=flow(lp[m])
                    if n<6 or abs(im)<0.3: continue
                    i=last_in(tt,off-elo,off-en)
                    if i is None or not 1.5<=float(lp[i])<=10: continue
                    st='BUY' if im>0 else 'SELL'
                    if st not in best or abs(im)>best[st][0]: best[st]=(abs(im),tt,lp,i)
                for st,(_,tt,lp,i) in best.items():
                    q_,how=exit_price(tt[i+1:],lp[i+1:],off); C[sp+' exit '+how]+=1
                    if q_ is None: C[sp+' dropped, no exit, no result read']+=1; continue
                    for lab,v in trades(st,fill(tt,lp,i,'B'),fill(tt,lp,i,'L'),q_): rows.append((sp,lab,off,mk,v))
            del X
        d0=d1
    print(sp,"done, rows so far",len(rows),f"{time.time()-T0:.0f}s",flush=True)
con.close()
print("counts",dict(sorted(C.items())),flush=True)
T=pd.DataFrame(rows,columns=['sp','lab','off','mk','v']); o=[]
for (sp,l),x in T.groupby(['sp','lab']):
    med=x.off.median(); h=np.where(x.off<=med,1,2); d=line(x.v.values,h); v=x.v.values
    o.append(dict(sport=sp,line=l,n=d['n'],markets=x.mk.nunique(),per10=round(d['per10'],3),t=round(d['t'],2),h1=round(d['h1'],3),h2=round(d['h2'],3),n1=d['n1'],n2=d['n2'],no_top=round(np.delete(v,v.argmax()).mean(),3),PASS=d['PASS']))
O=pd.DataFrame(o).sort_values('t',ascending=False)
print("lines",len(O)); print(O.to_string(index=False))
print("SURVIVORS"); S=O[O.PASS]; print(S.to_string(index=False) if len(S) else "none",flush=True)
PY
