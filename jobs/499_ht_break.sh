#!/bin/bash
set -o pipefail
# 499_ht_break (Finder 2026-11-06, queue item 296, Finder's own, source a): in and out across the half-time break, by wall clock. Rule pushed in the queue (fd41c8e) before any price. Read only, no tables written. Prints only, so a pass is an upper bound.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line,back_hedge,lay_hedge,step
from lib_official import bk,ly,fill,last_in,first_in,secs,checks,group,load_results
import lib_cand; lib_cand._checks(); checks()
pd.set_option('display.width',220); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',200)
def bandof(p): return '<=2' if p<=2 else '2-4' if p<=4 else '4-10' if p<=10 else None
def exit_print(tt,lp,off):
    """(price, how). Last print KO+58 to KO+60; else first print after KO+60 to KO+90; else None."""
    j=last_in(tt,off+58*60,off+60*60)
    if j is not None: return float(lp[j]),'IN_WINDOW'
    j=first_in(tt,off+60*60+1e-6,off+90*60)
    return (float(lp[j]),'LATE') if j is not None else (None,'NONE')
# known answers, worked by hand
assert bandof(2)=='<=2' and bandof(2.02)=='2-4' and bandof(4)=='2-4' and bandof(10)=='4-10' and bandof(10.5) is None
_t=np.array([0.,58*60.,59*60.,60*60+30.,80*60.]); _p=np.array([3.,2.,2.1,2.2,2.3])
assert exit_print(_t,_p,0.)==(2.1,'IN_WINDOW')
assert exit_print(np.array([61*60.]),np.array([2.2]),0.)==(2.2,'LATE') and exit_print(np.array([91*60.]),np.array([2.2]),0.)==(None,'NONE')
# Back 2.0 -> 1.99 fill is the caller's; back_hedge: backed at 2.0, out at 2.0 laying 2.02: 10*(2/2.02-1) = -0.0990
assert abs(back_hedge(2.0,2.0)-10*(2/2.02-1))<1e-9
# Laid at 2.0, out at 2.0 backing 1.99: stake 10, 10*(1-2/1.99) = -0.0503
assert abs(lay_hedge(2.0,2.0)-10*(1-2/1.99))<1e-9
print("checks: OK",flush=True); T0=time.time()
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
TY=['MATCH_ODDS','OVER_UNDER_15','OVER_UNDER_25','OVER_UNDER_35']
RS,dr=load_results(con,TY); print("official markets",len(RS),"dropped, not one winner",dr,f"{time.time()-T0:.0f}s",flush=True)
C=Counter(); rows=[]; moves=[]
def month_chunks():
    for y,ms in ((2024,range(1,12)),(2026,range(5,12))):
        for m in ms:
            a=pd.Timestamp(y,m,1); e=a+pd.offsets.MonthBegin(1)
            if (y,m)>=(2026,8):   # Sep 2026 alone broke the 2.5 GB cap on the first run of 499_ht_break: read these by 5 days, no change to the rule
                while a<e:
                    b=min(a+pd.Timedelta(days=5),e); yield str(a.date()),str(b.date()); a=b
            else: yield str(a.date()),str(e.date())
for lo,hi in month_chunks():
    X=pd.read_sql("SELECT market_id,event_name ev,market_type ty,market_time mt,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type=ANY(%s) AND inplay AND ltp>=1.01 AND ltp<1000 AND ts>=market_time+interval '50 minutes' AND ts<=market_time+interval '90 minutes' AND market_time>=%s AND market_time<%s",con,params=(TY,lo,hi))
    if X.empty: print(lo,"no rows",flush=True); continue
    X['tt']=secs(X.ts); X['off']=secs(X.mt); X=X.sort_values('tt',kind='stable').drop_duplicates(['market_id','sel','tt'])
    nm=0
    for (ev,ty,off),G_ in X.groupby(['ev','ty','off'],sort=False):
        ids=sorted(G_.market_id.unique())
        if len(ids)>1: C['second id']+=1
        mk=ids[0]
        if ' v ' not in ev: C['no H v A']+=1; continue
        if group(ev): C['women or youth']+=1; continue
        h,a=ev.split(' v ',1); nm+=1
        for s,y in G_[G_.market_id==mk].groupby('sel',sort=False):
            if ty=='MATCH_ODDS': r={h:'HOME',a:'AWAY','The Draw':'DRAW'}.get(s)
            else: r=ty[-2:]+' '+s.split()[0]
            if r is None: C['name mismatch']+=1; continue
            tt,lp=y.tt.values,y.ltp.values; i=first_in(tt,off+50*60,off+53*60)
            if i is None: C['no entry print']+=1; continue
            if float(lp[i])>10: C['over 10']+=1; continue
            b=bandof(float(lp[i])); L,B=fill(tt,lp,i,'L'),fill(tt,lp,i,'B')
            q,how=exit_print(tt[i+1:],lp[i+1:],off); C['exit '+how]+=1
            if q is None:
                if mk in RS and s in RS[mk]:
                    w=RS[mk][s]; vb,vl=bk(B,w),ly(L,w); C['settled at result']+=1
                else: C['no exit, no result, dropped']+=1; continue
            else:
                a_=step(B,-1)
                vb=None if a_<=1.01 else back_hedge(a_,q); vl=lay_hedge(step(L,1),q)
                moves.append((r,b,float(lp[i]),q))
            lab=f"{r} {b}"
            if vb is not None: rows.append((lab,'back_out',off,ev,vb))
            rows.append((lab,'lay_out',off,ev,vl))
    print(lo,"rows",len(X),"markets",nm,"cands",len(rows),f"{time.time()-T0:.0f}s",flush=True); del X
con.close()
print("counts",dict(sorted(C.items())),flush=True)
M=pd.DataFrame(moves,columns=['r','b','p0','q']); M['pts']=100*(1/M.p0-1/M.q)
print("mean move across the break, entry print to exit print, implied points (+ = price rose), no costs"); print(M.groupby(['r','b']).pts.agg(['count','mean','std']).round(3).to_string())
T=pd.DataFrame(rows,columns=['lab','side','off','ev','v']).drop_duplicates(['lab','side','off','ev'])
med=T.off.median(); T['h']=np.where(T.off<=med,1,2); print("halves split at",pd.Timestamp(med,unit='s',tz='UTC'),"games",T[['off','ev']].drop_duplicates().shape[0],flush=True)
o=[]
for (l,s),x in T.groupby(['lab','side']):
    if len(x)<2: continue
    d=line(x.v.values,x.h.values); v=x.v.values; xl=np.delete(v,v.argmax()).mean()
    o.append(dict(line=f"{l} {s}",n=d['n'],per10=round(d['per10'],3),t=round(d['t'],2),h1=round(d['h1'],3),h2=round(d['h2'],3),n1=d['n1'],n2=d['n2'],no_top=round(xl,3),PASS=d['PASS']))
O=pd.DataFrame(o).sort_values('t',ascending=False)
print("lines",len(O)); print(O.head(15).to_string(index=False)); print("worst"); print(O.tail(4).to_string(index=False))
print("SURVIVORS"); S=O[O.PASS]; print(S.to_string(index=False) if len(S) else "none",flush=True)
PY
