#!/bin/bash
set -o pipefail
# 499_last_race (Finder 2026-11-07, queue item 373, Finder's own, source b): last race of the card at BSP, card from the bf_hist_other schedule. Engine from jobs/499_race_clash.sh. Rule pushed before any price. Read only. ppwap runs to the off: a pass is an upper bound.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_000_000_000,2_000_000_000))  # this job only
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
def card_states(M):
    """M has course, day, t: FIRST, LAST_MEET or MID per row, and the last race anywhere that day."""
    first=M.groupby(['course','day']).t.transform('min'); last=M.groupby(['course','day']).t.transform('max')
    return np.where(M.t==first,'FIRST',np.where(M.t==last,'LAST_MEET','MID')),M.t==M.groupby('day').t.transform('max')
# known answers, worked by hand
_m=pd.DataFrame(dict(course=['a']*3+['b']*2,day=[1]*5,t=[1.,2.,3.,2.5,4.])); _s,_l=card_states(_m); assert list(_s)==['FIRST','MID','LAST_MEET','FIRST','LAST_MEET'] and list(_l)==[False,False,False,False,True]
assert list(band([3,3.01,6,12,30,30.5]))==['<=3','3-6','3-6','6-12','12-30','30+']
assert abs(pnl_back(3.0,1)-19.6)<1e-9 and pnl_lay(3.0,1)==-10 and abs(pnl_lay(3.0,0)-4.9)<1e-9
print("checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
cur.execute("SELECT DISTINCT event_name,extract(epoch from market_time)::float8 FROM bf_hist_other WHERE sport='Horse Racing' AND market_type='WIN' AND country IN ('GB','IE')")
M=pd.DataFrame(cur.fetchall(),columns=['course','t']).drop_duplicates()
M['dt']=pd.to_datetime(M.t,unit='s'); M['day']=M.dt.dt.date; pm=M.groupby(M.dt.dt.strftime('%Y-%m')).t.size(); GOOD=set(pm[pm>=500].index); M=M[M.dt.dt.strftime('%Y-%m').isin(GOOD)]
print(f"card rows {len(M):,}, months kept {len(GOOD)}, {time.time()-T0:.0f}s",flush=True)
cnt=M.groupby(['course','day']).t.nunique(); print("races a meeting-day:",cnt.value_counts().sort_index().to_dict(),flush=True)
keep=cnt[cnt>=6].index; M=M.set_index(['course','day']).loc[keep].reset_index()
M['st'],M['lastday']=card_states(M)
print("meeting-days kept",len(keep),"state rows",M.st.value_counts().to_dict(),"last of the day",int(M.lastday.sum()),flush=True)
R=pd.read_sql("SELECT menu_hint course,event_id,event_dt,selection_id,win_lose,bsp::float8 bsp,ppwap::float8 ppwap,pp_vol::float8 pp_vol FROM racing_bsp WHERE market='win'",con); con.close()
bad=R.bsp.isna()|(R.bsp<=1)|R.ppwap.isna()|(R.ppwap<=1)|R.pp_vol.isna()|R.win_lose.isna()
W=R[~R.event_id.isin(set(R.event_id[bad]))].copy(); bk=(1/W.ppwap).groupby(W.event_id).sum(); W=W[W.event_id.isin(bk[(bk>=1.0)&(bk<=1.40)].index)]
E=W.drop_duplicates('event_id')[['event_id','event_dt','course']].copy(); dt=pd.to_datetime(E.event_dt)
keyset=set(zip(M.course,M.t)); cand={}
for z in ('UTC','Europe/London'):
    ts=dt.dt.tz_localize(z,ambiguous='NaT',nonexistent='NaT').map(lambda x:x.timestamp() if x==x else np.nan); hit=[(c,t) in keyset for c,t in zip(E.course,ts)]; cand[z]=(ts,float(np.mean(hit)))
print("share of races on the kept card by zone",{k:round(v[1],3) for k,v in cand.items()},flush=True)
z=max(cand,key=lambda k:cand[k][1]); E['t']=cand[z][0].values; print("zone used",z,flush=True)
E=E.merge(M[['course','t','st','lastday']],on=['course','t'],how='inner'); print("races matched",E.event_id.nunique(),E.st.value_counts().to_dict(),"last of day",int(E.lastday.sum()),flush=True)
assert not E.duplicated('event_id').any()
W=W.merge(E[['event_id','t','st','lastday']],on='event_id')
W['bd']=band(W.ppwap.values); r=W.groupby('event_id').ppwap.rank(method='min'); tie=W.groupby('event_id').ppwap.transform(lambda s:(s==s.min()).sum())>1; W['fav']=(r==1)&(~tie)
W['vb']=pnl_back(back_px(W.bsp.values),W.win_lose.values); W['vl']=pnl_lay(lay_px(W.bsp.values),W.win_lose.values)
print("mean runners a race",W.groupby('st').size().div(W.groupby('st').event_id.nunique()).round(1).to_dict(),"mean pp_vol",W.groupby('st').pp_vol.mean().round(0).to_dict(),flush=True)
def tab(x,col,**k):
    v=x[col].values; md=np.median(x.t.values); h=x.t.values<md; a,b=v[h],v[~h]; tr=tgame(v,x.event_id.values)
    return dict(**k,n=len(v),races=x.event_id.nunique(),per10=v.mean(),t=tstat(v),tr=tr,n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,won=(x.win_lose==1).mean(),imp=(1/x.bsp).mean(),maxwin=v.max(),PASS=passes(len(v),len(a),len(b),tr,a.mean() if len(a) else 0,b.mean() if len(b) else 0,v.mean()))
out=[]
for st,xs in list(W.groupby('st'))+[('LAST_DAY',W[W.lastday])]:
    for bd,x in xs.groupby('bd'):
        for s,c in (('back','vb'),('lay','vl')): out.append(tab(x,c,state=st,line=bd,side=s))
    x=xs[xs.fav]
    for s,c in (('back','vb'),('lay','vl')): out.append(tab(x,c,state=st,line='FAV',side=s))
O=pd.DataFrame(out); T=O[O.state!='MID'].sort_values('tr',ascending=False); C=O[O.state=='MID'].sort_values('tr',ascending=False)
print(f"\n== ITEM 373: {len(T)} lines by t per race\n",T.round(3).to_string(index=False)); print("\n-- control MID, cannot pass\n",C.round(3).to_string(index=False))
Z=T[T.PASS==True]; print(f"\n== SURVIVORS: {len(Z)}\n",Z.round(3).to_string(index=False) if len(Z) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
