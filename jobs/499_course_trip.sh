#!/bin/bash
set -o pipefail
# 499_course_trip (Finder 2026-11-05, queue item 120, Finder's own, source c): course and trip at BSP. Rule written in the queue before any price was read. The number 499 is reused with a new slug: 450-499 are all taken.
# DATA racing_bsp win markets, UK/IE. Race filter, favourite, costs and dead heats as jobs/499_meeting_today.sh. COURSE selection uses earlier calendar years only and is walked forward, so no year sees itself. Favourite error uses 1/ppwap.
# LIMIT ppwap runs to the off and the box holds part of each year's racing. A pass is an upper bound.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,re,time,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import LD,tstat,passes
import lib_cand; lib_cand._checks()
pd.set_option('display.width',250); pd.set_option('display.max_rows',200); pd.set_option('display.max_columns',40)
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
def course(h):
    """'IRE / Listowel 22nd Sep' or 'GB / Uttoxeter 31st Dec' or 'Kempton 14th Jan' -> course name."""
    s=re.sub(r'^[A-Z]+\s*/\s*','',str(h)).strip()
    return re.sub(r'\s+\d{1,2}(st|nd|rd|th)\s+\w+$','',s).strip()
def furlongs(n):
    m=re.match(r'^\s*(?:(\d+)m)?\s*(?:(\d+)f)?',str(n))
    if not m or (m[1] is None and m[2] is None): return None
    return 8*int(m[1] or 0)+int(m[2] or 0)
def trip(n):
    """Trip class from the race name; None if it cannot be read."""
    s=str(n)
    if re.search(r'(?i)\bchs\b|chase',s): return 'CHASE'
    if re.search(r'(?i)\bhrd\b|hurdle',s): return 'HURDLE'
    if re.search(r'(?i)\bnhf\b|\binhf\b',s): return None     # bumpers are neither, left out as the item lists five classes
    f=furlongs(s)
    if f is None: return None
    return 'FLAT5-6f' if f<=6 else 'FLAT7f-1m2f' if f<=10 else 'FLAT1m3f+'
BANDS=[(3,6,'B3-6'),(6,12,'B6-12'),(12,30,'B12-30'),(30,1e9,'B30+')]
def leg(p,isfav):
    if isfav: return 'FAV'
    for lo,hi,n in BANDS:
        if lo<p<=hi: return n
    return None
def quarters(err):
    """{course:error}: labels the bottom and top quarter, 4+ courses needed. Ties by name."""
    k=sorted(err,key=lambda z:(err[z],z)); m=len(k)//4; o={}
    if m==0: return o
    for z in k[:m]: o[z]='BOTQ'
    for z in k[-m:]: o[z]='TOPQ'
    return o
# known answers, worked by hand
assert abs(pnl_back(3.0,1)-19.6)<1e-9 and pnl_back(3.0,0)==-10 and abs(pnl_lay(3.0,0)-4.9)<1e-9 and pnl_lay(3.0,1)==-10
assert course('IRE / Listowel 22nd Sep')=='Listowel' and course('GB / Uttoxeter 31st Dec')=='Uttoxeter' and course('Kempton 14th Jan')=='Kempton' and course('Gowran Park 20th Sep')=='Gowran Park'
assert furlongs('2m7f Hcap Hrd')==23 and furlongs('6f Hcap')==6 and furlongs('1m Mdn')==8 and furlongs('1m1f Grp 3')==9 and furlongs('Hcap') is None
assert trip('2m7f Hcap Hrd')=='HURDLE' and trip('3m Hcap Chs')=='CHASE' and trip('6f Hcap')=='FLAT5-6f' and trip('1m Mdn')=='FLAT7f-1m2f' and trip('1m2f Hcap')=='FLAT7f-1m2f' and trip('1m3f Hcap')=='FLAT1m3f+' and trip('2m Mdn NHF') is None and trip('To Be Placed') is None
assert quarters(dict(a=1,b=2,c=3,d=4))=={'a':'BOTQ','d':'TOPQ'} and quarters(dict(a=1))=={}
print("checks: OK",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
R=pd.read_sql("SELECT country,event_id,event_name,menu_hint,event_dt,selection_id,win_lose,bsp::float bsp,ppwap::float ppwap FROM racing_bsp WHERE market='win'",con); con.close()
bad=R.bsp.isna()|(R.bsp<=1)|R.ppwap.isna()|(R.ppwap<=1)|R.win_lose.isna()
W=R[~R.event_id.isin(set(R.event_id[bad]))].copy()
bk_=(1/W.ppwap).groupby(W.event_id).sum(); ok=bk_[(bk_>=1.0)&(bk_<=1.40)].index; W=W[W.event_id.isin(ok)].copy()
W['course']=W.menu_hint.map(course); W['trip']=W.event_name.map(trip); W['yr']=pd.to_datetime(W.event_dt).dt.year
mn=W.groupby('event_id').ppwap.transform('min'); cnt=(W.ppwap==mn).groupby(W.event_id).transform('sum'); W['isfav']=(W.ppwap==mn)&(cnt==1)
W['leg']=[leg(p,f) for p,f in zip(W.ppwap,W.isfav)]; W['big']=(W.ppwap>12)&~W.isfav
W['bk']=pnl_back(back_px(W.bsp.values),W.win_lose.values); W['ly']=pnl_lay(lay_px(W.bsp.values),W.win_lose.values); W['won']=W.win_lose>=1; W['imp']=1/W.ppwap
med=W.event_dt.median(); W['h']=np.where(W.event_dt<med,1,2)
print(f"races {W.event_id.nunique()}, runners {len(W)}, courses {W.course.nunique()}, years {W.yr.value_counts().sort_index().to_dict()}; median {med}; trip classes {W.drop_duplicates('event_id').trip.value_counts(dropna=False).to_dict()}; {time.time()-T0:.0f}s",flush=True)
print("sample courses:",sorted(W.course.unique())[:12],flush=True)
F=W[W.isfav]; rows=[]
for Y in sorted(W.yr.unique()):
    if Y<2023: continue
    prev=F[F.yr<Y]; g=prev.assign(e=prev.won.astype(float)-prev.imp).groupby('course').e.agg(['mean','count']); err=g[g['count']>=150]['mean'].to_dict(); lab=quarters(err)
    print(f"  {Y}: courses with 150+ earlier races {len(err)}; bottom {[k for k,v in lab.items() if v=='BOTQ'][:4]} top {[k for k,v in lab.items() if v=='TOPQ'][:4]}",flush=True)
    now=W[W.yr==Y]
    for c,tg in lab.items():
        x=now[now.course==c]
        rows.append(x[x.isfav].assign(st='COURSE_'+tg,lg='FAV'))
        rows.append(x[x.big].assign(st='COURSE_'+tg,lg='B12+'))
    for c in err:
        x=now[now.course==c]; rows.append(x[x.isfav].assign(st='COURSE_CTRL',lg='FAV')); rows.append(x[x.big].assign(st='COURSE_CTRL',lg='B12+'))
T=W[W.trip.notna()&W['leg'].notna()]; rows.append(T.assign(st='TRIP_'+T.trip.astype(str),lg=T['leg']))
L=pd.concat(rows,ignore_index=True); out=[]
for (st,lg),d in L.groupby(['st','lg']):
    for side,c in (('BACK','bk'),('LAY','ly')):
        v=d[c].values; a=v[d.h.values==1]; b=v[d.h.values==2]; tr=tstat(d.groupby('event_id')[c].sum().values)
        P=passes(len(v),len(a),len(b),tstat(v),a.mean() if len(a) else -1,b.mean() if len(b) else -1,v.mean()) and tr>=3.5
        out.append(dict(state=st,leg=lg,side=side,n=len(v),races=d.event_id.nunique(),per10=v.mean(),t=tstat(v),t_race=tr,n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,won=d.won.mean(),imp=d.imp.mean(),maxwin=v.max(),PASS=P))
O=pd.DataFrame(out); print(f"\nlines {len(O)}, n>=300 {(O.n>=300).sum()}")
print("\n== TOP 15 by t, n>=150\n",O[O.n>=150].sort_values('t',ascending=False).head(15).round(3).to_string(index=False))
print("\n== BOTTOM 6 by t, n>=150\n",O[O.n>=150].sort_values('t').head(6).round(3).to_string(index=False))
print("\n== COURSE lines\n",O[O.state.str.startswith('COURSE')].round(3).to_string(index=False))
Y=O[O.PASS]; print(f"\n== SURVIVORS: {len(Y)} of {len(O)}\n",Y.round(3).to_string(index=False) if len(Y) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
