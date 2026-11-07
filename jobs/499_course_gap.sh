#!/bin/bash
set -o pipefail
# 499_course_gap (Finder 2026-11-07, queue item 413, Finder's own, source c): a course's first meeting after a gap, at BSP, gap from the bf_hist_other schedule, not from racing_bsp, which holds only part of each card. Engine from jobs/499_last_race.sh. Rule pushed before any price. Read only. ppwap runs to the off: a pass is an upper bound.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_000_000_000,2_000_000_000))  # this job only
import sys,re,time,datetime as dtm,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import LD,tstat,passes
from lib_wom import tgame
import lib_cand; lib_cand._checks()
pd.set_option('display.width',250); pd.set_option('display.max_rows',120); pd.set_option('display.max_columns',40)
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
DATE=re.compile(r" \d{1,2}(st|nd|rd|th) [A-Z][a-z]{2}$")
def cname(s): return DATE.sub('',s)
def months_between(a,b):
    """Months from a to b inclusive, 'YYYY-MM'."""
    o=[]; y,m=a.year,a.month
    while (y,m)<=(b.year,b.month):
        o.append(f"{y:04d}-{m:02d}"); m+=1
        if m==13: y+=1; m=1
    return o
def gaps(days,good):
    """days: sorted distinct dates at one course. {day:gap in days}; None for the first day seen, or if any month across the gap is not fully on the schedule."""
    out={}; prev=None
    for d in days:
        if prev is None: out[d]=None
        else: out[d]=(d-prev).days if all(x in good for x in months_between(prev,d)) else None
        prev=d
    return out
def gap_state(g):
    if g is None: return None
    return 'G1' if g==1 else 'G2_7' if g<=7 else 'G8_30' if g<=30 else 'G31_120' if g<=120 else 'G121+'
# known answers, worked by hand
D=dtm.date
assert cname('Doncaster 12th Sep')=='Doncaster' and cname('Gowran Park 1st Oct')=='Gowran Park' and cname('Newmarket')=='Newmarket' and cname('Ayr 22nd Sep')=='Ayr'
assert months_between(D(2025,11,30),D(2026,2,1))==['2025-11','2025-12','2026-01','2026-02'] and months_between(D(2025,3,1),D(2025,3,9))==['2025-03']
_g={'2025-01','2025-02','2025-03','2025-05','2025-06'}
_o=gaps([D(2025,1,1),D(2025,1,2),D(2025,1,10),D(2025,3,1),D(2025,5,1),D(2025,5,3)],_g)
assert _o[D(2025,1,1)] is None and _o[D(2025,1,2)]==1 and _o[D(2025,1,10)]==8 and _o[D(2025,3,1)]==50   # 21 days to 31 Jan plus 28 of Feb plus 1
assert _o[D(2025,5,1)] is None and _o[D(2025,5,3)]==2   # April is not on the schedule, so that gap is unknown, not long
assert [gap_state(x) for x in (None,1,2,7,8,30,31,120,121)]==[None,'G1','G2_7','G2_7','G8_30','G8_30','G31_120','G31_120','G121+']
assert list(band([3,3.01,6,12,30,30.5]))==['<=3','3-6','3-6','6-12','12-30','30+']
assert abs(pnl_back(3.0,1)-19.6)<1e-9 and pnl_back(3.0,0)==-10 and abs(pnl_lay(3.0,0)-4.9)<1e-9 and pnl_lay(3.0,1)==-10 and pnl_lay(3.0,2)==-2.5
assert back_px(2.0)==1.99 and lay_px(2.0)==2.02
print("checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
cur.execute("SELECT DISTINCT event_name,extract(epoch from market_time)::float8 FROM bf_hist_other WHERE sport='Horse Racing' AND market_type='WIN' AND country IN ('GB','IE')")
M=pd.DataFrame(cur.fetchall(),columns=['course','t']).drop_duplicates()
M['dt']=pd.to_datetime(M.t,unit='s'); M['day']=M.dt.dt.date; M['ym']=M.dt.dt.strftime('%Y-%m'); M['cn']=M.course.map(cname)
pm=M.groupby('ym').t.size(); print("races per month on the schedule",pm.to_dict(),flush=True)
GOOD=set(pm[pm>=500].index); print("months kept",len(GOOD),"of",len(pm),f"{time.time()-T0:.0f}s",flush=True)
G={}
for c,x in M.groupby('cn'):
    for d,g in gaps(sorted(x.day.unique()),GOOD).items(): G[(c,d)]=g
M['gap']=[G[(c,d)] for c,d in zip(M.cn,M.day)]; M['st']=[gap_state(None if g is None or g!=g else int(g)) for g in M.gap]
md_=M.drop_duplicates(['cn','day']); print("meeting-days by state",md_.st.value_counts(dropna=False).to_dict(),flush=True)
print("sample G121+ meetings",md_[md_.st=='G121+'][['cn','day','gap']].sort_values('day').head(20).values.tolist(),flush=True)
print("sample G31_120 meetings",md_[md_.st=='G31_120'][['cn','day','gap']].sort_values('day').head(12).values.tolist(),flush=True)
M=M[M.st.notna()]
R=pd.read_sql("SELECT menu_hint course,event_id,event_dt,selection_id,win_lose,bsp::float8 bsp,ppwap::float8 ppwap,pp_vol::float8 pp_vol FROM racing_bsp WHERE market='win'",con); con.close()
bad=R.bsp.isna()|(R.bsp<=1)|R.ppwap.isna()|(R.ppwap<=1)|R.pp_vol.isna()|R.win_lose.isna()
W=R[~R.event_id.isin(set(R.event_id[bad]))].copy(); bk=(1/W.ppwap).groupby(W.event_id).sum(); W=W[W.event_id.isin(bk[(bk>=1.0)&(bk<=1.40)].index)]
E=W.drop_duplicates('event_id')[['event_id','event_dt','course']].copy(); dt=pd.to_datetime(E.event_dt)
keyset=set(zip(M.course,M.t)); cand={}
for z in ('UTC','Europe/London'):
    ts=dt.dt.tz_localize(z,ambiguous='NaT',nonexistent='NaT').map(lambda x:x.timestamp() if x==x else np.nan); hit=[(c,t) in keyset for c,t in zip(E.course,ts)]; cand[z]=(ts,float(np.mean(hit)))
print("share of races on the schedule by zone",{k:round(v[1],3) for k,v in cand.items()},flush=True)
z=max(cand,key=lambda k:cand[k][1]); E['t']=cand[z][0].values; print("zone used",z,flush=True)
E=E.merge(M[['course','t','st']].drop_duplicates(['course','t']),on=['course','t'],how='inner'); print("races matched",E.event_id.nunique(),E.st.value_counts().to_dict(),flush=True)
assert not E.duplicated('event_id').any()
W=W.merge(E[['event_id','t','st']],on='event_id')
W['bd']=band(W.ppwap.values); r=W.groupby('event_id').ppwap.rank(method='min'); tie=W.groupby('event_id').ppwap.transform(lambda s:(s==s.min()).sum())>1; W['fav']=(r==1)&(~tie)
W['vb']=pnl_back(back_px(W.bsp.values),W.win_lose.values); W['vl']=pnl_lay(lay_px(W.bsp.values),W.win_lose.values)
print("mean runners a race",W.groupby('st').size().div(W.groupby('st').event_id.nunique()).round(1).to_dict(),"mean pp_vol",W.groupby('st').pp_vol.mean().round(0).to_dict(),flush=True)
def tab(x,col,**k):
    v=x[col].values; md=np.median(x.t.values); h=x.t.values<md; a,b=v[h],v[~h]; tr=tgame(v,x.event_id.values)
    return dict(**k,n=len(v),races=x.event_id.nunique(),per10=v.mean(),t=tstat(v),tr=tr,n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,won=(x.win_lose==1).mean(),imp=(1/x.bsp).mean(),maxwin=v.max(),PASS=passes(len(v),len(a),len(b),tr,a.mean() if len(a) else 0,b.mean() if len(b) else 0,v.mean()))
out=[]
for st,xs in W.groupby('st'):
    for bd,x in xs.groupby('bd'):
        for s,c in (('back','vb'),('lay','vl')): out.append(tab(x,c,state=st,line=bd,side=s))
    x=xs[xs.fav]
    for s,c in (('back','vb'),('lay','vl')): out.append(tab(x,c,state=st,line='FAV',side=s))
O=pd.DataFrame(out); T=O[O.state!='G2_7'].sort_values('tr',ascending=False); C=O[O.state=='G2_7'].sort_values('tr',ascending=False)
print(f"\n== ITEM 413: {len(T)} lines by t per race\n",T.round(3).to_string(index=False)); print("\n-- control G2_7, cannot pass\n",C.round(3).to_string(index=False))
Z=T[T.PASS==True]; print(f"\n== SURVIVORS: {len(Z)}\n",Z.round(3).to_string(index=False) if len(Z) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
