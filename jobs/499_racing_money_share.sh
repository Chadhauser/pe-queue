#!/bin/bash
set -o pipefail
# 499_racing_money_share (Finder 2026-11-05, queue items 100, 101, Finder's own, sources b and c): share of matched money v the price, thin races and surface, at BSP. Rules written in the queue before any price was read.
# DATA racing_bsp win markets, UK/IE. A race is used only if every runner has a BSP, a ppwap and a pp_vol, and the 1/ppwap book is 1.00-1.40, as jobs/499_race_shape.sh.
# ENTRY BSP, one tick adverse, 2% on profit, £10 risk, to result, nothing dropped; dead heats as jobs/499_race_shape.sh. Bands on ppwap, never on BSP, which is unknown when the order goes in.
# LIMIT ppwap and pp_vol run to the off, so a live rule needs the last minutes' figures: read a pass as an upper bound. The box holds part of each year's racing.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import LD,tstat,passes
import lib_cand; lib_cand._checks()
pd.set_option('display.width',250); pd.set_option('display.max_rows',500); pd.set_option('display.max_columns',40)
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
def money_ratio(W):
    """R = runner's share of the race's pp_vol / its share of 1/ppwap."""
    g=W.groupby('event_id'); share=W.pp_vol/g.pp_vol.transform('sum'); ip=1/W.ppwap; imp=ip/ip.groupby(W.event_id).transform('sum'); return share/imp
AW=('Southwell','Newcastle','Wolverhampton','Kempton','Chelmsford','Dundalk')
JUMPS=r'(?i)\b(?:chs|hrd|hurdle|chase|nhf|inhf)\b'
def is_aw(h,name):
    """Course on the list and not a jumps race: Southwell, Newcastle and Kempton also race over jumps on turf."""
    return pd.Series(h).str.startswith(AW).values & ~pd.Series(name).str.contains(JUMPS,regex=True).values
# known answers, worked by hand
assert back_px(11.2)==11.0 and lay_px(11.2)==11.5 and back_px(2.0)==1.99 and lay_px(2.0)==2.02
assert abs(pnl_back(3.0,1)-19.6)<1e-9 and pnl_back(3.0,0)==-10 and abs(pnl_back(3.0,2)-4.9)<1e-9
assert abs(pnl_lay(3.0,0)-4.9)<1e-9 and pnl_lay(3.0,1)==-10 and pnl_lay(3.0,2)==-2.5
assert list(band([3,3.01,6,12,30,30.5]))==['<=3','3-6','3-6','6-12','12-30','30+']
_W=pd.DataFrame(dict(event_id=[1,1,2,2],ppwap=[2.,2.,2.,4.],pp_vol=[75.,25.,50.,50.])); _R=money_ratio(_W)
assert abs(_R[0]-1.5)<1e-9 and abs(_R[1]-0.5)<1e-9 and abs(_R[2]-0.75)<1e-9 and abs(_R[3]-1.5)<1e-9    # race 2: implied 2/3, 1/3; shares 1/2, 1/2
assert list(is_aw(['Southwell 8th Oct','Lingfield 10th Sep','Dundalk 1st Mar','Ascot 1st Jun','Southwell 4th Mar','Newcastle 23rd Dec','Newcastle 30th Nov'],['6f Hcap','6f Hcap','1m Mdn Stks','6f Hcap','2m App Hcap Chs','1m6f NHF','2m Grd1 Hrd']))==[True,False,True,False,False,False,False]
print("checks: OK",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
R=pd.read_sql("SELECT country,event_id,event_name,menu_hint,event_dt,selection_id,win_lose,bsp::float bsp,ppwap::float ppwap,pp_vol::float pp_vol FROM racing_bsp WHERE market='win'",con); con.close()
print(f"win rows {len(R)}, races {R.event_id.nunique()}, {R.event_dt.min()} to {R.event_dt.max()}; {time.time()-T0:.0f}s",flush=True)
bad=R.bsp.isna()|(R.bsp<=1)|R.ppwap.isna()|(R.ppwap<=1)|R.pp_vol.isna()|(R.pp_vol<0)
W=R[~R.event_id.isin(set(R.event_id[bad]))].copy()
bk_=(1/W.ppwap).groupby(W.event_id).sum(); ok=bk_[(bk_>=1.0)&(bk_<=1.40)].index; W=W[W.event_id.isin(ok)].copy()
W=W[W.groupby('event_id').pp_vol.transform('sum')>0].copy()
W['R']=money_ratio(W); W['band']=band(W.ppwap.values)
med=W.event_dt.median(); W['h']=np.where(W.event_dt<med,1,2)
W['vol']=W.groupby('event_id').pp_vol.transform('sum')
rv=W[W.h==1].drop_duplicates('event_id').vol; lo,hi=rv.quantile(.2),rv.quantile(.8)
W['bk']=pnl_back(back_px(W.bsp.values),W.win_lose.values); W['ly']=pnl_lay(lay_px(W.bsp.values),W.win_lose.values)
print(f"races used {W.event_id.nunique()}, runners {len(W)}; median date {med}; race volume cuts from the first half {lo:.0f}, {hi:.0f}; R quartiles {W.R.quantile([.25,.5,.75]).round(2).tolist()}",flush=True)
S100={'R<0.7':W.R<.7,'R0.7-1.3':(W.R>=.7)&(W.R<1.3),'R>=1.3':W.R>=1.3,'R>=2':W.R>=2}
S101={'ALLCTRL':W.R>-1,'THIN':W.vol<=lo,'DEEP':W.vol>=hi,'AW':is_aw(W.menu_hint.values,W.event_name.values),'IRE':W.country=='ire','UK':W.country=='uk'}
def tb(it,st,bd,sd,x,c):
    v=x[c].values; h=x.h.values; a=v[h==1]; b=v[h==2]; n=len(v); t=tstat(v); byr=x.groupby('event_id')[c].sum().values; tr=tstat(byr)
    return dict(item=it,state=st,band=bd,side=sd,n=n,races=len(byr),per10=v.mean() if n else np.nan,t=t,t_race=tr,n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,maxwin=v.max() if n else np.nan,PASS=passes(n,len(a),len(b),t,a.mean() if len(a) else -1,b.mean() if len(b) else -1,v.mean() if n else -1) and tr>=3.5)
o=[]
for it,SS in ((100,S100),(101,S101)):
    for st,m in SS.items():
        x=W[np.asarray(m)]
        for bd,y in list(x.groupby('band'))+[('ALL',x)]:
            for sd,c in (('BACK','bk'),('LAY','ly')): o.append(tb(it,st,bd,sd,y,c))
O=pd.DataFrame(o)
for it,x in O.groupby('item'):
    big=x[x.n>=300]
    print(f"\n== item {it}: lines {len(x)}, n>=300 {len(big)}, positive there {int((big.per10>0).sum())}, pass {int(x.PASS.sum())}. Top 15 by t, n>=150"); print(x[x.n>=150].sort_values('t',ascending=False).head(15).round(3).to_string(index=False))
print("\n== every line"); print(O.round(3).to_string(index=False))
print("\n== SURVIVORS (bar: n>=300, n>=150 per half, both halves > 0, t and t by race >= 3.5, mean >= +0.15, upper bound)"); S=O[O.PASS]; print(S.round(3).to_string(index=False) if len(S) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
