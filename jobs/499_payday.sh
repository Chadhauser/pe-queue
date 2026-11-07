#!/bin/bash
set -o pipefail
# 499_payday (Finder 2026-11-07, queue item 374, Finder's own, source c): the Saturday after UK payday. Racing engine from jobs/499_race_clash.sh, football engine from jobs/499_home_dog.sh. Rule pushed before any price. Read only. ppwap runs to the off and football is LTP only: a pass is an upper bound.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))  # this job only
import sys,time,datetime as dtm,calendar,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import LD,step,back_settle,lay_settle,line,tstat,passes
from lib_wom import tgame
import lib_cand; lib_cand._checks()
pd.set_option('display.width',240); pd.set_option('display.max_rows',120); pd.set_option('display.max_columns',30)
T0=time.time(); UK=(39,40,41,42,179,180)
def last_working(y,m):
    d=dtm.date(y,m,calendar.monthrange(y,m)[1])
    while d.weekday()>=5: d-=dtm.timedelta(days=1)
    return d
def pay_saturday(y,m):
    d=last_working(y,m)
    while d.weekday()!=5: d+=dtm.timedelta(days=1)
    return d
def pay_set(y0,y1):
    return {pay_saturday(y,m) for y in range(y0,y1+1) for m in range(1,13)}
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
def bk(x,won):
    a=step(x,-1); return None if a<=1.01 else back_settle(a,won)
def ly(x,won): return lay_settle(step(x,1),won)
def dog_band(p): return '2-3' if 2<=p<3 else '3-4' if 3<=p<4 else '4-6' if 4<=p<6 else '6-12' if 6<=p<12 else None
def fav_band(p): return '<=1.5' if p<=1.5 else '1.5-2' if p<=2 else None
# known answers, worked by hand from a calendar: Oct 2026 ends Sat 31, last working Fri 30, Saturday 31. Nov 2026 ends Mon 30, Saturday 5 Dec. May 2026 ends Sun 31, last working Fri 29, Saturday 30 May. Jan 2026 ends Sat 31, last working Fri 30, Saturday 31 Jan.
assert last_working(2026,10)==dtm.date(2026,10,30) and pay_saturday(2026,10)==dtm.date(2026,10,31)
assert last_working(2026,11)==dtm.date(2026,11,30) and pay_saturday(2026,11)==dtm.date(2026,12,5)
assert last_working(2026,5)==dtm.date(2026,5,29) and pay_saturday(2026,5)==dtm.date(2026,5,30)
assert pay_saturday(2026,1)==dtm.date(2026,1,31) and pay_saturday(2026,1).weekday()==5
assert dtm.date(2026,12,5) in pay_set(2026,2026) and dtm.date(2026,11,7) not in pay_set(2026,2026)
assert list(band([3,3.01,6,12,30,30.5]))==['<=3','3-6','3-6','6-12','12-30','30+'] and abs(pnl_lay(3.0,0)-4.9)<1e-9
print("checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
PAY=pay_set(2019,2027)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
# RACING
R=pd.read_sql("SELECT country,event_id,event_dt,selection_id,win_lose,bsp::float8 bsp,ppwap::float8 ppwap,pp_vol::float8 pp_vol FROM racing_bsp WHERE market='win'",con)
print("countries",R.country.value_counts().to_dict(),flush=True)
bad=R.bsp.isna()|(R.bsp<=1)|R.ppwap.isna()|(R.ppwap<=1)|R.pp_vol.isna()|R.win_lose.isna()
W=R[~R.event_id.isin(set(R.event_id[bad]))].copy(); bk_=(1/W.ppwap).groupby(W.event_id).sum(); W=W[W.event_id.isin(bk_[(bk_>=1.0)&(bk_<=1.40)].index)]
W=W[W.country=='uk'].copy(); assert len(W) and set(W.country)=={'uk'}   # review fix: the first filter tested upper-case names against 'uk' and let Ireland through
W['ts']=pd.to_datetime(W.event_dt); W['day']=W.ts.dt.date; W=W[W.ts.dt.dayofweek==5].copy(); W['st']=np.where(W.day.isin(PAY),'PAY','OTHER')
print("racing Saturdays",W.groupby('st').day.nunique().to_dict(),"races",W.groupby('st').event_id.nunique().to_dict(),flush=True)
W['bd']=band(W.ppwap.values); r=W.groupby('event_id').ppwap.rank(method='min'); tie=W.groupby('event_id').ppwap.transform(lambda s:(s==s.min()).sum())>1; W['fav']=(r==1)&(~tie)
W['vb']=pnl_back(back_px(W.bsp.values),W.win_lose.values); W['vl']=pnl_lay(lay_px(W.bsp.values),W.win_lose.values)
def tab(x,col,**k):
    v=x[col].values; md=x.ts.median(); h=(x.ts<md).values; a,b=v[h],v[~h]; tr=tgame(v,x.event_id.values)
    return dict(**k,n=len(v),races=x.event_id.nunique(),per10=v.mean(),t=tstat(v),tr=tr,n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,won=(x.win_lose==1).mean(),imp=(1/x.bsp).mean(),maxwin=v.max(),PASS=passes(len(v),len(a),len(b),tr,a.mean() if len(a) else 0,b.mean() if len(b) else 0,v.mean()))
out=[]
for st,xs in W.groupby('st'):
    for bd,x in xs.groupby('bd'):
        for s,c in (('back','vb'),('lay','vl')): out.append(tab(x,c,state=st,line=bd,side=s))
    x=xs[xs.fav]
    for s,c in (('back','vb'),('lay','vl')): out.append(tab(x,c,state=st,line='FAV',side=s))
O=pd.DataFrame(out).sort_values('tr',ascending=False)
print("\n== RACING PAY, by t per race\n",O[O.state=='PAY'].round(3).to_string(index=False)); print("\n-- control OTHER, cannot pass\n",O[O.state=='OTHER'].round(3).to_string(index=False),flush=True)
SR=O[(O.state=='PAY')&(O.PASS==True)]
# FOOTBALL
G=pd.read_sql("""SELECT m.event_id,f.fixture_id,f.league_id,f.league,f.season,f.kickoff,f.home,f.away,f.hg,f.ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL AND f.season IN (2024,2025) AND f.league_id IN (39,40,41,42,179,180)""",con)
EV=pd.read_sql("SELECT fixture_id,min(coalesce(minute,0)) gm FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal') AND coalesce(minute,0)<=2 GROUP BY 1",con,params=(list(map(int,G.fixture_id)),))
first_goal=dict(zip(EV.fixture_id,EV.gm)); parts=[]
for i in range(0,len(G),1000):
    P=pd.read_sql("SELECT event_id,sel,minute,m,ltp::float8 ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt='MO' AND sel IN ('HOME','AWAY') AND minute>=0 AND minute<=2 AND ltp>=1.01 AND ltp<1000",con,params=(list(G.event_id.iloc[i:i+1000]),))
    parts.append(P.sort_values(['event_id','sel','minute','m']).drop_duplicates(['event_id','sel']))
con.close(); P=pd.concat(parts,ignore_index=True).merge(G,on='event_id'); print(f"\nUK mapped games {len(G)}, with a print {P.event_id.nunique()}",flush=True)
P['lag']=(pd.to_datetime(P.m,utc=True)-pd.to_datetime(P.kickoff,utc=True)).dt.total_seconds()/60
badr=(P.lag<-5)|(P.lag>20); gm=P.fixture_id.map(first_goal); kn=gm.notna()&(gm<P.minute); P=P[~badr&~kn]
F=[]
for (e,fx,s,ko,hg,ag),x in P.groupby(['event_id','fixture_id','season','kickoff','hg','ag']):
    pr=dict(zip(x.sel,x.ltp))
    if len(pr)<2 or pr['HOME']==pr['AWAY']: continue
    t=pd.Timestamp(ko).tz_convert('Europe/London')
    if t.dayofweek!=5: continue
    st='PAY' if t.date() in PAY else 'OTHER'; fav,dog=('HOME','AWAY') if pr['HOME']<pr['AWAY'] else ('AWAY','HOME'); res='HOME' if hg>ag else 'AWAY' if ag>hg else 'DRAW'
    for role,who,b in (('FAV',fav,fav_band(pr[fav])),('DOG',dog,dog_band(pr[dog]))):
        if not b: continue
        p=pr[who]; w=res==who; v=bk(p,w)
        if v is not None: F.append((st,role,b,'back',s,fx,p,w,v))
        F.append((st,role,b,'lay',s,fx,p,w,ly(p,w)))
F=pd.DataFrame(F,columns='state role band side season fx x won v'.split()); assert not F.duplicated(['state','role','band','side','fx']).any()
print("football games",F.groupby('state').fx.nunique().to_dict(),flush=True)
o2=[]
for k,x in F.groupby(['state','role','band','side']):
    l=line(x.v.values,np.where(x.season==2024,1,2)); o2.append(dict(state=k[0],role=k[1],band=k[2],side=k[3],n=l['n'],per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],won=x.won.mean(),imp=(1/x.x).mean(),maxwin=l['maxwin'],PASS=l['PASS']))
O2=pd.DataFrame(o2).sort_values('t',ascending=False)
print("\n== FOOTBALL PAY, by t\n",O2[O2.state=='PAY'].round(3).to_string(index=False)); print("\n-- control OTHER, cannot pass\n",O2[O2.state=='OTHER'].round(3).to_string(index=False))
SF=O2[(O2.state=='PAY')&(O2.PASS==True)]
print(f"\n== SURVIVORS: racing {len(SR)}, football {len(SF)}"); print(SR.round(3).to_string(index=False) if len(SR) else "racing none"); print(SF.round(3).to_string(index=False) if len(SF) else "football none")
print(f"total {time.time()-T0:.0f}s")
PY
