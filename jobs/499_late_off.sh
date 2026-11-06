#!/bin/bash
set -o pipefail
# 499_late_off (Finder 2026-11-06, queue item 297, Finder's own, source c; pricing from jobs/499_race_clash.sh): a race still not off three minutes after its time, at BSP. Rule pushed in the queue before any price. Read only, no tables written. ppwap runs to the off, so a pass is an upper bound.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_000_000_000,2_000_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import LD,tstat,passes,line
import lib_cand; lib_cand._checks()
pd.set_option('display.width',230); pd.set_option('display.max_rows',100); pd.set_option('display.max_columns',40)
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
def course(s):
    """'GB / Uttoxeter 31st Dec' or 'Uttoxeter 31st Dec' -> 'Uttoxeter 31st Dec'."""
    return str(s).split(' / ')[-1].strip()
def delay_state(d): return 'LATE5' if d>=5 else 'LATE3' if d>=3 else 'ONTIME'
# known answers, worked by hand
assert course('GB / Uttoxeter 31st Dec')=='Uttoxeter 31st Dec' and course('Nottingham 15th Oct')=='Nottingham 15th Oct'
assert delay_state(2.99)=='ONTIME' and delay_state(3)=='LATE3' and delay_state(4.99)=='LATE3' and delay_state(5)=='LATE5'
assert back_px(11.2)==11.0 and lay_px(11.2)==11.5 and back_px(2.0)==1.99 and lay_px(2.0)==2.02
assert abs(pnl_back(3.0,1)-19.6)<1e-9 and pnl_back(3.0,0)==-10 and abs(pnl_back(3.0,2)-4.9)<1e-9 and abs(pnl_lay(3.0,0)-4.9)<1e-9 and pnl_lay(3.0,1)==-10 and pnl_lay(3.0,2)==-2.5
assert list(band([3,3.01,6,12,30,30.5]))==['<=3','3-6','3-6','6-12','12-30','30+']
print("checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
cur.execute("""SELECT event_name,extract(epoch from market_time)::float8 t,extract(epoch from min(ts) filter (where inplay))::float8 f FROM bf_hist_other WHERE sport='Horse Racing' AND market_type='WIN' AND country IN ('GB','IE') GROUP BY 1,2""")
S=pd.DataFrame(cur.fetchall(),columns=['course','t','f']); n0=len(S); S=S.dropna(subset=['f']); S['d']=(S.f-S.t)/60
print(f"schedule {n0:,} races, with an in-play print {len(S):,}, {time.time()-T0:.0f}s; delay min quantiles",S.d.quantile([.5,.9,.95,.99]).round(2).to_dict(),flush=True)
print("states on the whole schedule",S.d.map(delay_state).value_counts().to_dict(),flush=True)
R=pd.read_sql("SELECT event_id,event_dt,menu_hint,selection_id,win_lose,bsp::float8 bsp,ppwap::float8 ppwap,country FROM racing_bsp WHERE market='win' AND event_dt>='2024-08-31'",con); con.close()
bad=R.bsp.isna()|(R.bsp<=1)|R.ppwap.isna()|(R.ppwap<=1)|R.win_lose.isna()
print(f"racing_bsp rows {len(R):,}, races {R.event_id.nunique():,}, races dropped for a bad row {R.event_id[bad].nunique():,}",flush=True)
W=R[~R.event_id.isin(set(R.event_id[bad]))].copy(); bkk=(1/W.ppwap).groupby(W.event_id).sum(); ok=bkk[(bkk>=1.0)&(bkk<=1.40)].index; W=W[W.event_id.isin(ok)]
W['course']=W.menu_hint.map(course); dt=pd.to_datetime(W.event_dt).dt.tz_localize('Europe/London',ambiguous='NaT',nonexistent='NaT')
W['t']=(dt-pd.Timestamp('1970-01-01',tz='UTC'))/pd.Timedelta(seconds=1)
print("clock-change rows dropped",int(W.t.isna().sum()),flush=True); W=W.dropna(subset=['t'])
W=W.merge(S[['course','t','d']],on=['course','t'],how='left')
print(f"races matched {W[W.d.notna()].event_id.nunique():,} of {W.event_id.nunique():,}",flush=True); W=W[W.d.notna()].copy()
W['state']=W.d.map(delay_state); W['bd']=band(W.ppwap.values)
W['fav']=W.groupby('event_id').ppwap.rank(method='first')==1
print("races by state",W.drop_duplicates('event_id').state.value_counts().to_dict(),flush=True)
med=W.t.median(); W['h']=np.where(W.t<=med,1,2); print("halves split at",pd.Timestamp(med,unit='s',tz='UTC'),flush=True)
W['vb']=pnl_back(back_px(W.bsp.values),W.win_lose.values); W['vl']=pnl_lay(lay_px(W.bsp.values),W.win_lose.values)
o=[]
def rec(st,leg,x):
    for col,side in (('vb','back'),('vl','lay')):
        if len(x)<2: continue
        d=line(x[col].values,x.h.values); tr=tstat(x.groupby('event_id')[col].sum().values)
        v=x[col].values; o.append(dict(state=st,line=f"{leg} {side}",n=d['n'],races=x.event_id.nunique(),per10=round(d['per10'],3),t=round(d['t'],2),tr=round(tr,2),h1=round(d['h1'],3),h2=round(d['h2'],3),n1=d['n1'],n2=d['n2'],no_top=round(np.delete(v,v.argmax()).mean(),3),PASS=d['PASS'] and tr>=3.5))
for st,sel in (('LATE3',W.d>=3),('LATE5',W.d>=5),('ONTIME',W.d<3)):
    x=W[sel]; rec(st,'FAV',x[x.fav])
    for _,_,b in BANDS: rec(st,b,x[x.bd==b])
O=pd.DataFrame(o); C=O[O.state=='ONTIME']; O=O[O.state!='ONTIME'].sort_values('t',ascending=False)
print("lines",len(O)); print(O.to_string(index=False))
print("control, ONTIME, not scored"); print(C.to_string(index=False))
print("SURVIVORS"); S_=O[O.PASS]; print(S_.to_string(index=False) if len(S_) else "none",flush=True)
PY
