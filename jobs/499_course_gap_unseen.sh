#!/bin/bash
set -o pipefail
# 499_course_gap_unseen (Finder 2026-11-07, queue item 416, Finder's own, source c, from item 413): lay the clear favourite on a course's second day running at BSP, on racing_bsp races outside item 413's schedule. The day before comes from racing_bsp itself, which holds part of each card, so some controls are really second days, which blurs the gap and cannot flatter it. Rule pushed before this job read a price. Read only. ppwap runs to the off: a pass is an upper bound.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_000_000_000,2_000_000_000))  # this job only
import sys,re,time,datetime as dtm,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import LD,tstat,passes
from lib_wom import tgame
import lib_cand; lib_cand._checks()
pd.set_option('display.width',250); pd.set_option('display.max_rows',80); pd.set_option('display.max_columns',40)
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
PFX=re.compile(r"^[A-Z]{2,3} / ")
DATE=re.compile(r" \d{1,2}(st|nd|rd|th) [A-Z][a-z]{2}$")
def course(h): return DATE.sub('',PFX.sub('',h))
def day2(days):
    """Sorted distinct dates at one course: {day: True if the day before is also there}."""
    s=set(days); return {d:(d-dtm.timedelta(days=1)) in s for d in days}
# known answers, worked by hand
D=dtm.date
assert course('IRE / Listowel 22nd Sep')=='Listowel' and course('GB / Uttoxeter 31st Dec')=='Uttoxeter' and course('Kempton 14th Jan')=='Kempton' and course('Gowran Park 20th Sep')=='Gowran Park'
assert day2([D(2023,1,1),D(2023,1,2),D(2023,1,4)])=={D(2023,1,1):False,D(2023,1,2):True,D(2023,1,4):False}
assert day2([D(2022,12,31),D(2023,1,1)])[D(2023,1,1)] is True
assert abs(pnl_lay(3.0,0)-4.9)<1e-9 and pnl_lay(3.0,1)==-10 and pnl_lay(3.0,2)==-2.5 and abs(pnl_back(3.0,1)-19.6)<1e-9
print("checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
cur.execute("SELECT min(market_time),max(market_time) FROM bf_hist_other WHERE sport='Horse Racing' AND market_type='WIN' AND country IN ('GB','IE') AND market_time>='2024-09-01' AND market_time<'2024-09-03'")
print("schedule start check",cur.fetchone(),flush=True)
R=pd.read_sql("SELECT menu_hint,event_id,event_dt,selection_id,win_lose,bsp::float8 bsp,ppwap::float8 ppwap,pp_vol::float8 pp_vol FROM racing_bsp WHERE market='win'",con); con.close()
R['course']=R.menu_hint.map(course); R['day']=pd.to_datetime(R.event_dt).dt.date
G={}
for c,x in R.groupby('course'): G.update({(c,d):v for d,v in day2(sorted(x.day.unique())).items()})
bad=R.bsp.isna()|(R.bsp<=1)|R.ppwap.isna()|(R.ppwap<=1)|R.pp_vol.isna()|R.win_lose.isna()
W=R[~R.event_id.isin(set(R.event_id[bad]))].copy(); bk=(1/W.ppwap).groupby(W.event_id).sum(); W=W[W.event_id.isin(bk[(bk>=1.0)&(bk<=1.40)].index)]
W['t']=pd.to_datetime(W.event_dt)
LO,HI=pd.Timestamp('2024-09-01'),pd.Timestamp('2026-10-01')
W=W[(W.t<LO)|(W.t>=HI)]   # races item 413 did not read
W['g1']=[G[(c,d)] for c,d in zip(W.course,W.day)]
r=W.groupby('event_id').ppwap.rank(method='min'); tie=W.groupby('event_id').ppwap.transform(lambda s:(s==s.min()).sum())>1
F=W[(r==1)&(~tie)].copy(); F['tt']=(F.t-pd.Timestamp('1970-01-01'))/pd.Timedelta(seconds=1)
print(f"races {W.event_id.nunique():,}, clear favourites {len(F):,}, second-day races {int(F.g1.sum()):,}, dates {F.t.min()} to {F.t.max()}, by year {F.t.dt.year.value_counts().sort_index().to_dict()}, {time.time()-T0:.0f}s",flush=True)
F['vb']=pnl_back(back_px(F.bsp.values),F.win_lose.values); F['vl']=pnl_lay(lay_px(F.bsp.values),F.win_lose.values)
out=[]
for nm,x in (('SECOND DAY',F[F.g1]),('CONTROL no day before on the box',F[~F.g1])):
    md=np.median(x.tt.values); h=x.tt.values<md
    for s,c in (('lay','vl'),('back','vb')):
        v=x[c].values; a,b=v[h],v[~h]; tr=tgame(v,x.event_id.values)
        out.append(dict(line=nm,side=s,n=len(v),races=x.event_id.nunique(),per10=v.mean(),t=tstat(v),tr=tr,n1=len(a),h1=a.mean(),n2=len(b),h2=b.mean(),won=(x.win_lose==1).mean(),imp=(1/x.bsp).mean(),maxwin=v.max(),no_top=np.delete(v,v.argmax()).mean(),PASS=(nm=='SECOND DAY' and s=='lay' and passes(len(v),len(a),len(b),tr,a.mean(),b.mean(),v.mean()))))
O=pd.DataFrame(out); print("\n== ITEM 416, the scored line is SECOND DAY lay\n",O.round(3).to_string(index=False))
Z=O[O.PASS==True]; print(f"\n== SURVIVORS: {len(Z)}\n",Z.round(3).to_string(index=False) if len(Z) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
