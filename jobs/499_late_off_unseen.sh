#!/bin/bash
set -o pipefail
# 499_late_off_unseen (Finder 2026-11-06, queue item 299, Finder's own, source c; from jobs/499_late_off.sh, unresolved scoring from jobs/499_doubles_truth.sh): lay the favourite in a late race, races item 297 could not see, at a real print after T+3, inferred result. Rule pushed in the queue before any price. Read only, no tables written. Prints only, so a pass is an upper bound.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line,tstat
from lib_official import bk,ly,fill,last_in,first_in,secs,checks
import lib_cand; lib_cand._checks(); checks()
pd.set_option('display.width',230); pd.set_option('display.max_rows',100); pd.set_option('display.max_columns',40)
def course(s): return str(s).split(' / ')[-1].strip()
def infer(lastip):
    """lastip {runner: last in-play print}. Winner if exactly one at or under 1.05, else None."""
    w=[s for s,p in lastip.items() if p<=1.05]
    return w[0] if len(w)==1 else None
def prob(lastip,s):
    """Runner s's chance at last-print odds, overround removed."""
    t=sum(1/p for p in lastip.values())
    return (1/lastip[s])/t
def scored(price,side,lastip,s):
    """(pnl, resolved). Resolved: settle on the inferred winner. Unresolved: expected P&L at last-print odds, item 278."""
    f=ly if side=='L' else bk; w=infer(lastip)
    win,lose=f(price,True),f(price,False)
    if win is None: return None,w is not None
    if w is not None: return (win if w==s else lose),True
    p=prob(lastip,s); return p*win+(1-p)*lose,False
# known answers, worked by hand
assert infer({'a':1.02,'b':200.})=='a' and infer({'a':1.5,'b':3.}) is None and infer({'a':1.02,'b':1.04}) is None
assert abs(prob({'a':2.,'b':2.},'a')-.5)<1e-9 and abs(prob({'a':2.,'b':4.},'a')-(2/3))<1e-9
# Lay 2.0 fills 2.02: stake 9.8039, wins 9.6078 after 2%; loses 10. Unresolved at 50%: (9.6078-10)/2 = -0.1961.
assert scored(2.0,'L',{'a':1.02,'b':900.},'a')==(-10.0,True) and abs(scored(2.0,'L',{'a':1.02,'b':900.},'b')[0]-10/1.02*.98)<1e-9
_v,_r=scored(2.0,'L',{'a':2.,'b':2.},'a'); assert not _r and abs(_v-(10/1.02*.98-10)/2)<1e-9
assert course('GB / Uttoxeter 31st Dec')=='Uttoxeter 31st Dec'
print("checks: OK",flush=True); T0=time.time()
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
cur.execute("""SELECT market_id,event_name,extract(epoch from market_time)::float8 t,extract(epoch from min(ts) filter (where inplay))::float8 f FROM bf_hist_other WHERE sport='Horse Racing' AND market_type='WIN' AND country IN ('GB','IE') GROUP BY 1,2,3""")
S=pd.DataFrame(cur.fetchall(),columns=['mk','course','t','f']).dropna(subset=['f']); S['d']=(S.f-S.t)/60
R=pd.read_sql("SELECT event_id,event_dt,menu_hint,selection_name,win_lose FROM racing_bsp WHERE market='win' AND event_dt>='2024-08-31'",con)
R['course']=R.menu_hint.map(course); dt=pd.to_datetime(R.event_dt).dt.tz_localize('Europe/London',ambiguous='NaT',nonexistent='NaT')
R['t']=(dt-pd.Timestamp('1970-01-01',tz='UTC'))/pd.Timedelta(seconds=1); R=R.dropna(subset=['t'])
keys=set(zip(R.course,R.t)); S['seen']=[(c,t) in keys for c,t in zip(S.course,S.t)]
L=S[S.d>=3].copy(); print(f"races with a print {len(S):,}, matched to racing_bsp {int(S.seen.sum()):,}; LATE3+ {len(L):,}, of them unseen {int((~L.seen).sum()):,}, {time.time()-T0:.0f}s",flush=True)
OFF={(c,t):g for (c,t),g in R.groupby(['course','t'])}
C=Counter(); rows=[]; ids=list(L.mk); info=L.set_index('mk')
for i0 in range(0,len(ids),400):
    X=pd.read_sql("SELECT market_id,market_time mt,sel,inplay,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Horse Racing' AND market_id=ANY(%s) AND ltp>=1.01 AND ltp<1000 AND ts>=market_time-interval '5 minutes'",con,params=(ids[i0:i0+400],))
    if not len(X): continue
    X['tt']=secs(X.ts); X=X.sort_values('tt',kind='stable').drop_duplicates(['market_id','sel','tt'])
    for mk,G_ in X.groupby('market_id',sort=False):
        off=float(info.t[mk]); C['late races']+=1; lastp={}; lastip={}; pre={}
        for s,y in G_.groupby('sel',sort=False):
            pm=y[~y.inplay]; ip=y[y.inplay]
            pre[s]=(pm.tt.values,pm.ltp.values)
            j=last_in(pre[s][0],off-300,off+180)
            if j is not None: lastp[s]=float(pre[s][1][j])
            if len(ip): lastip[s]=float(ip.ltp.values[-1])
        if len(lastp)<3: C['under 3 priced']+=1; continue
        lo=min(lastp.values()); fav=[s for s,p in lastp.items() if p==lo]
        if len(fav)>1: C['level']+=1; continue
        fav=fav[0]; a,b=pre[fav]; i=first_in(a,off+180,off+86400)
        if i is None: C['no pre-off print after T+3']+=1; continue
        if not lastip or fav not in lastip: C['no in-play print for the favourite']+=1; continue
        # official result on matched races, for the calibration
        off_res=None; seen=bool(info.seen[mk])
        if seen:
            g=OFF.get((info.course[mk],off))
            if g is not None:
                w=g[g.selection_name==fav].win_lose
                if len(w)==1 and pd.notna(w.iloc[0]): off_res=int(w.iloc[0])
        L_,B_=fill(a,b,i,'L'),fill(a,b,i,'B')
        if L_>50: C['over 50']+=1; continue
        vl,rs=scored(L_,'L',lastip,fav); vb,_=scored(B_,'B',lastip,fav)
        ofl=None if off_res is None else ly(L_,off_res==1) if off_res in (0,1) else None
        rows.append((mk,off,seen,float(info.d[mk]),vl,vb,rs,ofl,off_res,infer(lastip)==fav,infer(lastip) is not None))
    print("races read",min(i0+400,len(ids)),"rows",len(rows),f"{time.time()-T0:.0f}s",flush=True); del X
con.close()
print("counts",dict(sorted(C.items())),flush=True)
T=pd.DataFrame(rows,columns=['mk','off','seen','d','vl','vb','res','ofl','off_res','inf_won','inf_any']).drop_duplicates('mk')
U=T[~T.seen].copy(); K=T[T.seen].copy()
print(f"traded: unseen {len(U):,}, resolved share {U.res.mean():.3f}; seen {len(K):,}, resolved share {K.res.mean():.3f}",flush=True)
K2=K[K.ofl.notna()]; print(f"CALIBRATION seen races with official result n {len(K2)}: official lay {K2.ofl.astype(float).mean():+.3f} t {tstat(K2.ofl.astype(float).values):.2f}; same races inferred + last-print odds {K2.vl.mean():+.3f} t {tstat(K2.vl.values):.2f}; agreement of inferred winner with official among resolved {((K2.inf_won)==(K2.off_res==1))[K2.inf_any].mean():.3f}",flush=True)
med=U.off.median(); U['h']=np.where(U.off<=med,1,2); print("halves split at",pd.Timestamp(med,unit='s',tz='UTC'),flush=True)
o=[]
for nm,sel in (('LATE3 FAV',U.d>=3),('LATE5 FAV, context',U.d>=5),('3-5 min only, context',(U.d>=3)&(U.d<5))):
    x=U[sel]
    for side,col in (('lay','vl'),('back','vb')):
        y=x[x[col].notna()]; d=line(y[col].values,y.h.values); v=y[col].values
        o.append(dict(line=f"{nm} {side}",n=d['n'],per10=round(d['per10'],3),t=round(d['t'],2),h1=round(d['h1'],3),h2=round(d['h2'],3),n1=d['n1'],n2=d['n2'],no_top=round(np.delete(v,v.argmax()).mean(),3),PASS=d['PASS']))
O=pd.DataFrame(o); print(O.to_string(index=False))
r=U[U.res]; print(f"LATE3 lay resolved only (flatters, for reference) n {len(r)} {r.vl.mean():+.3f} t {tstat(r.vl.values):.2f}; won {r.inf_won.mean():.3f}",flush=True)
print("SURVIVORS"); S_=O[O.PASS & O.line.eq('LATE3 FAV lay')]; print(S_.to_string(index=False) if len(S_) else "none",flush=True)
PY
