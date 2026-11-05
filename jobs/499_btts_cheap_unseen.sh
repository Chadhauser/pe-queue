#!/bin/bash
set -o pipefail
# 499_btts_cheap_unseen (Finder 2026-11-05, queue item 136, from jobs/499_ko_cross_market.sh): BTTS cheap against MO and OU2.5 at the first in-play print, on the 2026 tape, which did not choose the line. Rule written in the queue before any 2026 price was read. Read only.
# TAPE bf_hist_other Soccer MATCH_ODDS, OVER_UNDER_25, BOTH_TEAMS_TO_SCORE, Jun-Sep 2026, earliest in-play print per selection within 5 min of market time, keyed by event name and market time as market ids take two forms on this tape. RESULTS af_fixtures, lib_cand.loose, within 20 min of the af kick-off. A goal at af minute <= 5 drops the game, counted.
# MODEL as jobs/499_ko_cross_market.sh. Bias: walk-forward mean of the previous 300 games by kick-off, first 300 not traded. r <= -0.02: back Yes, lay No, one tick adverse, hold to FT. r >= +0.02 shown as a mirror, not scored. Halves by median date. BAR out of reach at this n: a negative read closes it.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(3_000_000_000,3_000_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import deque,Counter,defaultdict
from scipy.optimize import minimize
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import *
import lib_cand; lib_cand._checks()
T0=time.time(); N=11; I=np.arange(N); F_=np.cumprod(np.r_[1.,np.arange(1,N)])
def pmf(l): return np.exp(-l)*l**I/F_
def probs(lh,la):
    M=np.outer(pmf(lh),pmf(la)); M=M/M.sum(); S=I[:,None]+I[None,:]
    return dict(H=np.tril(M,-1).sum(),D=np.trace(M),A=np.triu(M,1).sum(),OU25=M[S>2].sum(),BTTS=M[1:,1:].sum())
def fit(h,d,a,ov):
    def f(x):
        p=probs(np.exp(x[0]),np.exp(x[1])); return (p['H']-h)**2+(p['D']-d)**2+(p['A']-a)**2+(p['OU25']-ov)**2
    r=minimize(f,[np.log(1.4),np.log(1.1)],method='Nelder-Mead',options=dict(xatol=1e-3,fatol=1e-7,maxiter=200))
    return float(np.exp(r.x[0])),float(np.exp(r.x[1])),float(r.fun)
def nrm(a,b): return (1/a)/(1/a+1/b)
def bk(x,won):
    a=step(x,-1); return None if a<=1.01 else back_settle(a,won)
def ly(x,won): return lay_settle(step(x,1),won)
_p=probs(1.,1.); assert abs(_p['H']-_p['A'])<1e-9 and abs(_p['OU25']-(1-np.exp(-2)*5))<1e-5 and abs(_p['BTTS']-(1-np.exp(-1))**2)<1e-5
_x=probs(1.7,.9); _f=fit(_x['H'],_x['D'],_x['A'],_x['OU25']); assert abs(_f[0]-1.7)<.02 and abs(_f[1]-.9)<.02
assert abs(bk(2.04,True)-9.996)<1e-9 and ly(2.0,True)==-10.0 and abs(ly(2.0,False)-10/1.02*.98)<1e-9
print("checks: OK",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
FX=pd.read_sql("SELECT fixture_id,kickoff,home,away,hg,ag FROM af_fixtures WHERE status='FT' AND hg IS NOT NULL AND kickoff>='2026-05-31' AND kickoff<'2026-10-02' AND league_id NOT IN (2,3)",con)
FX['ks']=pd.to_datetime(FX.kickoff,utc=True).map(lambda t:t.timestamp()); FX['H']=FX.home.map(norm); FX['A']=FX.away.map(norm); FX=FX.sort_values('ks').reset_index(drop=True); ksv=FX.ks.values
E=pd.read_sql("SELECT DISTINCT fixture_id FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND coalesce(minute,0)<=5",con,params=(list(map(int,FX.fixture_id)),)); early=set(map(int,E.fixture_id))
parts=[]
for lo,hi in (('2026-05-31','2026-07-01'),('2026-07-01','2026-08-01'),('2026-08-01','2026-09-01'),('2026-09-01','2026-10-02')):
    P=pd.read_sql("""SELECT DISTINCT ON (market_type,event_name,market_time,sel) market_type,event_name,market_time,sel,ltp::float ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type IN ('MATCH_ODDS','OVER_UNDER_25','BOTH_TEAMS_TO_SCORE') AND inplay AND market_time>=%s AND market_time<%s AND ts<=market_time+interval '5 minutes' AND ltp>=1.01 AND ltp<1000 ORDER BY market_type,event_name,market_time,sel,ts""",con,params=(lo,hi)); parts.append(P)
    print(f"  {lo}: {len(P)} rows, {time.time()-T0:.0f}s",flush=True)
con.close(); P=pd.concat(parts,ignore_index=True); SK=Counter(); rec=[]
for (ev,mt),x in P.groupby(['event_name','market_time'],sort=False):
    if ' v ' not in ev: continue
    h,_,a=ev.partition(' v '); h=h.strip(); a=a.strip(); pr={(u,v):w for u,v,w in zip(x.market_type,x.sel,x.ltp)}
    y,no=pr.get(('BOTH_TEAMS_TO_SCORE','Yes')),pr.get(('BOTH_TEAMS_TO_SCORE','No'))
    ph,pd_,pa=pr.get(('MATCH_ODDS',h)),pr.get(('MATCH_ODDS','The Draw')),pr.get(('MATCH_ODDS',a))
    ov,un=pr.get(('OVER_UNDER_25','Over 2.5 Goals')),pr.get(('OVER_UNDER_25','Under 2.5 Goals'))
    if None in (y,no,ph,pd_,pa,ov,un): SK['a price missing']+=1; continue
    ms=pd.Timestamp(mt).timestamp(); lo,hi_=np.searchsorted(ksv,ms-1200),np.searchsorted(ksv,ms+1200,side='right')
    if hi_<=lo: SK['no af game in the window']+=1; continue
    idx=loose(norm(h),norm(a),[(FX.H.iat[i],FX.A.iat[i],i) for i in range(lo,hi_)])
    if idx is None: SK['no name match']+=1; continue
    f=FX.iloc[idx]
    if int(f.fixture_id) in early: SK['goal by minute 5']+=1; continue
    ih,idr,ia=1/ph,1/pd_,1/pa; z=ih+idr+ia
    if not .95<z<1.15: SK['MO book out of range']+=1; continue
    lh,la,err=fit(ih/z,idr/z,ia/z,nrm(ov,un))
    if err>.002: SK['fit error']+=1; continue
    rec.append((ms,int(f.fixture_id),nrm(y,no)-probs(lh,la)['BTTS'],y,no,bool(f.hg>0 and f.ag>0)))
rec.sort(key=lambda r:r[0]); print(f"games fitted {len(rec)}; {dict(SK)}; {time.time()-T0:.0f}s",flush=True)
B=deque(maxlen=300); rows=[]; i=0
while i<len(rec):
    j=i
    while j<len(rec) and rec[j][0]==rec[i][0]: j+=1
    for ms,fx,raw,y,no,won in rec[i:j]:
        if len(B)<300: continue
        r=raw-float(np.mean(B))
        if abs(r)<.02: continue
        d='CHEAP' if r<0 else 'RICH'
        v=bk(y,won)
        if v is not None: rows.append((d,'BACK Yes',fx,ms,y,won,v))
        rows.append((d,'LAY No',fx,ms,no,not won,ly(no,not won)))
    for x in rec[i:j]: B.append(x[2])
    i=j
R=pd.DataFrame(rows,columns=['d','side','fx','ms','x','won','v'])
if R.empty: print("no trades"); sys.exit(0)
R['h']=np.where(R.ms<R.ms.median(),1,2)
print("\n== r <= -0.02 is the scored line, r >= +0.02 a mirror, not scored")
for k,x in R.groupby(['d','side']):
    l=line(x.v.values,x.h.values); print(f"  {k[0]} {k[1]}: n {l['n']} per10 {l['per10']:+.3f} t {l['t']:.2f} h1 {l['h1']:+.3f} h2 {l['h2']:+.3f} won {x.won.mean():.3f} implied {(1/x.x).mean():.3f}")
print("\n== SURVIVORS: none can pass at this n; a negative read closes it"); print(f"done {time.time()-T0:.0f}s")
PY
