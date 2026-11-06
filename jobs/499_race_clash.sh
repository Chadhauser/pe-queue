#!/bin/bash
set -o pipefail
# 499_race_clash (Finder 2026-11-06, queue items 218, 219, Finder's own, source c): races that clash at BSP, and races 2-5 minutes apart (item 219, added after the first run found CLASH too rare; its lines unpriced until then). Rules pushed before those prices were read. The number 499 is reused: 450-499 are all taken.
# SCHEDULE every distinct bf_hist_other Horse Racing WIN GB, IE market. CLASH = another market within 2 minutes; QUIET = none within 10; the rest is the control and cannot pass. Scheduled times, so known in advance.
# TRADES racing_bsp win, UK/IE, every runner with BSP, ppwap, pp_vol, 1/ppwap book 1.00-1.40, inside the schedule's dates. BSP, one tick adverse, 2%, £10 risk, to result, dead heats as jobs/499_race_shape.sh. Bands on ppwap, never BSP. ppwap runs to the off: a pass is an upper bound.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(1_500_000_000,1_500_000_000))  # this job only
import sys,time,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import LD,tstat,passes
from lib_wom import tgame
import lib_cand; lib_cand._checks()
pd.set_option('display.width',250); pd.set_option('display.max_rows',100); pd.set_option('display.max_columns',40)
T0=time.time()
def back_px(p):
    p=np.asarray(p,dtype=float); return LD[np.clip(np.searchsorted(LD,p-1e-9,side='left')-1,0,len(LD)-1)]
def lay_px(p):
    p=np.asarray(p,dtype=float); return LD[np.clip(np.searchsorted(LD,p+1e-9,side='right'),0,len(LD)-1)]
def pnl_back(a,wl):
    a=np.asarray(a,dtype=float); wl=np.asarray(wl); g=np.where(wl==1,10*(a-1),np.where(wl==2,5*(a-1)-5,-10.0))
    return np.where(g>0,g*.98,g)
def pnl_lay(a,wl):
    a=np.asarray(a,dtype=float); wl=np.asarray(wl); s=10/(a-1); g=np.where(wl==1,-10.0,np.where(wl==2,-5+s/2,s))
    return np.where(g>0,g*.98,g)
BANDS=[(0,3,'<=3'),(3,6,'3-6'),(6,12,'6-12'),(12,30,'12-30'),(30,1e9,'30+')]
def band(p):
    p=np.asarray(p,dtype=float); o=np.empty(len(p),dtype=object)
    for lo,hi,n in BANDS: o[(p>lo)&(p<=hi)]=n
    return o
def nearest_other(sched,t):
    """sched sorted seconds of every market; t seconds of a race that IS in sched. Seconds to the nearest other market, np.inf if alone. A second market at the same second counts as distance 0."""
    i=np.searchsorted(sched,t,side='left'); best=np.inf; n=len(sched)
    if i>=n or sched[i]!=t: return None
    if i+1<n: best=min(best,sched[i+1]-t)
    if i>0: best=min(best,t-sched[i-1])
    return float(best)
def state(d): return None if d is None else 'CLASH' if d<=120 else 'QUIET' if d>600 else 'MID'
# known answers, worked by hand
_s=np.array([0.,300.,360.,1500.,1500.,3000.])
assert nearest_other(_s,300.)==60 and nearest_other(_s,0.)==300 and nearest_other(_s,3000.)==1500 and nearest_other(_s,1500.)==0 and nearest_other(_s,5.) is None and nearest_other(np.array([7.]),7.)==np.inf
assert state(120)=='CLASH' and state(121)=='MID' and state(600)=='MID' and state(601)=='QUIET' and state(None) is None and state(np.inf)=='QUIET'
assert back_px(11.2)==11.0 and lay_px(11.2)==11.5 and back_px(2.0)==1.99 and lay_px(2.0)==2.02
assert abs(pnl_back(3.0,1)-19.6)<1e-9 and pnl_back(3.0,0)==-10 and abs(pnl_back(3.0,2)-4.9)<1e-9 and abs(pnl_lay(3.0,0)-4.9)<1e-9 and pnl_lay(3.0,1)==-10 and pnl_lay(3.0,2)==-2.5
assert list(band([3,3.01,6,12,30,30.5]))==['<=3','3-6','3-6','6-12','12-30','30+']
print("checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
cur.execute("SHOW timezone"); print("server zone",cur.fetchone()[0],flush=True)
cur.execute("SELECT DISTINCT market_id,extract(epoch from market_time)::float8 FROM bf_hist_other WHERE sport='Horse Racing' AND market_type='WIN' AND country IN ('GB','IE')")
M=pd.DataFrame(cur.fetchall(),columns=['mid','t']).drop_duplicates()
print(f"schedule: rows {len(M):,}, distinct market ids {M.mid.nunique():,}, ids with more than one time {int((M.groupby('mid').t.nunique()>1).sum())}, {pd.to_datetime(M.t.min(),unit='s')} to {pd.to_datetime(M.t.max(),unit='s')}, {time.time()-T0:.0f}s",flush=True)
print("sample ids",list(M.mid.head(3)),flush=True)
M['day']=pd.to_datetime(M.t,unit='s').dt.date; pm=M.groupby(pd.to_datetime(M.t,unit='s').dt.strftime('%Y-%m')).mid.nunique(); print("markets by month",pm.to_dict(),flush=True)
GOOD=set(pm[pm>=500].index); M=M[pd.to_datetime(M.t,unit='s').dt.strftime('%Y-%m').isin(GOOD)]; print("months kept (500+ markets), the box's schedule is incomplete below that:",len(GOOD),flush=True)
print("markets a day, median",M.groupby('day').mid.nunique().median(),flush=True)
sched=np.sort(M.t.values)
R=pd.read_sql("SELECT country,event_id,event_dt,selection_id,win_lose,bsp::float8 bsp,ppwap::float8 ppwap,pp_vol::float8 pp_vol FROM racing_bsp WHERE market='win'",con); con.close()
print(f"racing_bsp win rows {len(R):,}, races {R.event_id.nunique():,}, {R.event_dt.min()} to {R.event_dt.max()}",flush=True)
bad=R.bsp.isna()|(R.bsp<=1)|R.ppwap.isna()|(R.ppwap<=1)|R.pp_vol.isna()|R.win_lose.isna()
W=R[~R.event_id.isin(set(R.event_id[bad]))].copy(); bk=(1/W.ppwap).groupby(W.event_id).sum(); ok=bk[(bk>=1.0)&(bk<=1.40)].index; W=W[W.event_id.isin(ok)]
E=W.drop_duplicates('event_id')[['event_id','event_dt']].copy(); dt=pd.to_datetime(E.event_dt)
# time zone: whichever reading of event_dt lands on a schedule time most often. No price is read here.
S=set(sched.tolist()); lo,hi=sched.min(),sched.max()
cand={}
for z in ('UTC','Europe/London'):
    ts=dt.dt.tz_localize(z,ambiguous='NaT',nonexistent='NaT').map(lambda x:x.timestamp() if x==x else np.nan); ins=(ts>=lo)&(ts<=hi); cand[z]=(ts,float(ts[ins].isin(S).mean()),int(ins.sum()))
print("share of racing_bsp races on a schedule time:",{k:(round(v[1],3),v[2]) for k,v in cand.items()},flush=True)
z=max(cand,key=lambda k:cand[k][1]); share=cand[z][1]
if share<0.85: print(f"ERROR: best zone {z} only {share:.3f} on the schedule: no verdict"); sys.exit(1)
E['ts']=cand[z][0].values; print("zone used",z,flush=True)
_d=[nearest_other(sched,t) if t==t else None for t in E.ts]   # a list: a pandas column turns None into NaN, and NaN read as MID filled the control with off-schedule races on the first run
E['st']=pd.Series([state(d) for d in _d],index=E.index,dtype=object); E['near']=pd.Series(['NEAR5' if d is not None and 120<d<=300 else None for d in _d],index=E.index,dtype=object)
_on=[d for d in _d if d is not None]; assert int(E.st.notna().sum())==len(_on),"a race off the schedule has a state"
print(f"races: {E.st.value_counts(dropna=False).to_dict()} (None = not on the schedule, left out); NEAR5 {int(E.near.notna().sum())}; median gap to the next race {np.median(_on):.0f}s",flush=True)
W=W.merge(E[['event_id','ts','st','near']],on='event_id'); W=W[W.st.notna()].copy()
W['bd']=band(W.ppwap.values); r=W.groupby('event_id').ppwap.rank(method='min'); tie=W.groupby('event_id').ppwap.transform(lambda s:(s==s.min()).sum())>1; W['fav']=(r==1)&(~tie)
W['vb']=pnl_back(back_px(W.bsp.values),W.win_lose.values); W['vl']=pnl_lay(lay_px(W.bsp.values),W.win_lose.values)
print("mean pp_vol per runner by state",W.groupby('st').pp_vol.mean().round(0).to_dict(),flush=True)
def tab(x,col,**k):
    v=x[col].values; md=np.median(x.ts.values); h=x.ts.values<md; a,b=v[h],v[~h]
    return dict(**k,n=len(v),races=x.event_id.nunique(),per10=v.mean(),t=tstat(v),tr=tgame(v,x.event_id.values),n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,won=(x.win_lose==1).mean(),imp=(1/x.bsp).mean(),maxwin=v.max(),PASS=passes(len(v),len(a),len(b),tstat(v),a.mean() if len(a) else 0,b.mean() if len(b) else 0,v.mean()))
out=[]
for st,xs in W.groupby('st'):
    for bd,x in xs.groupby('bd'):
        for s,c in (('back','vb'),('lay','vl')): out.append(tab(x,c,state=st,line=bd,side=s))
    x=xs[xs.fav]
    for s,c in (('back','vb'),('lay','vl')): out.append(tab(x,c,state=st,line='FAV',side=s))
xs=W[W.near.notna()]   # item 219, added after CLASH proved too rare: 2-5 minutes from another race. These races are also in MID, the control.
for bd,x in xs.groupby('bd'):
    for s,c in (('back','vb'),('lay','vl')): out.append(tab(x,c,state='NEAR5',line=bd,side=s))
x=xs[xs.fav]
for s,c in (('back','vb'),('lay','vl')): out.append(tab(x,c,state='NEAR5',line='FAV',side=s))
O=pd.DataFrame(out); T=O[O.state!='MID'].sort_values('t',ascending=False); C=O[O.state=='MID'].sort_values('t',ascending=False)
print(f"\n== ITEM 218: {len(T)} lines by t\n",T.round(3).to_string(index=False)); print("\n-- control MID, cannot pass\n",C.round(3).to_string(index=False))
Z=T[T.PASS==True]; print(f"\n== SURVIVORS: {len(Z)}\n",Z.round(3).to_string(index=False) if len(Z) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
