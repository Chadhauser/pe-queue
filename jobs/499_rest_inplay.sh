#!/bin/bash
set -o pipefail
# 499_rest_inplay (Finder 2026-11-07, queue item 372, Finder's own, source b, lay the field): a stand-alone resting bet in running, no BSP entry. Rule pushed before any price was summed. Read only.
# FILLS a lay at Q fills only if ipmin < Q; a back at Q only if ipmax > Q. Real prints, no time, so a pass still needs the in-play touch on ip_tape. One tick adverse, 2%, £10 risk, to result, dead heats as jobs/499_race_shape.sh.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))  # this job only
import sys,time,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import LD,tstat,passes
from lib_wom import tgame
import lib_cand; lib_cand._checks()
pd.set_option('display.width',250); pd.set_option('display.max_rows',150); pd.set_option('display.max_columns',40)
T0=time.time()
def back_px(p):
    p=np.asarray(p,dtype=float); return LD[np.clip(np.searchsorted(LD,p-1e-9,side='left')-1,0,len(LD)-1)]
def lay_px(p):
    p=np.asarray(p,dtype=float); return LD[np.clip(np.searchsorted(LD,p+1e-9,side='right'),0,len(LD)-1)]
def on_ladder(p):
    """nearest ladder price at or below p"""
    p=np.asarray(p,dtype=float); return LD[np.clip(np.searchsorted(LD,p+1e-9,side='right')-1,0,len(LD)-1)]
def pnl_back(a,wl):
    a=np.asarray(a,dtype=float); wl=np.asarray(wl); g=np.where(wl==1,10*(a-1),np.where(wl==2,5*(a-1)-5,-10.0))
    return np.where(g>0,g*.98,g)
def pnl_lay(a,wl):
    a=np.asarray(a,dtype=float); wl=np.asarray(wl); s=10/(a-1); g=np.where(wl==1,-10.0,np.where(wl==2,-5+s/2,s))
    return np.where(g>0,g*.98,g)
BANDS=[(0,1e9,'ALL'),(0,3,'<=3'),(3,6,'3-6'),(6,12,'6-12'),(12,30,'12-30'),(30,1e9,'30+')]
def lay_fill(ipmin,q): return np.asarray(ipmin,float)<np.asarray(q,float)
def back_fill(ipmax,q): return np.asarray(ipmax,float)>np.asarray(q,float)
# known answers, worked by hand
assert back_px(100.0)==95.0 and lay_px(1.1)==1.11 and back_px(5.0)==4.9 and lay_px(5.0)==5.1 and on_ladder(1.237)==1.23 and on_ladder(3.0)==3.0
assert abs(pnl_lay(1.11,0)-10/0.11*.98)<1e-9 and pnl_lay(1.11,1)==-10 and abs(pnl_back(5.0,1)-39.2)<1e-9 and pnl_back(5.0,0)==-10
assert list(lay_fill([1.1,1.09],1.1))==[False,True] and list(back_fill([5.0,5.1],5.0))==[False,True]
print("checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True
R=pd.read_sql("SELECT market,event_id,event_dt,selection_id,win_lose,bsp::float8 bsp,ipmin::float8 ipmin,ipmax::float8 ipmax FROM racing_bsp",con); con.close()
print(f"rows {len(R):,}, {R.event_dt.min()} to {R.event_dt.max()}",flush=True)
R=R[R.bsp.notna()&(R.bsp>1)&R.win_lose.notna()]
print(f"with bsp and result {len(R):,}; no in-play print, never filled, {int((R.ipmin.isna()|R.ipmax.isna()).sum()):,}",flush=True)
print("duplicates",int(R.duplicated(['market','event_id','selection_id']).sum()),flush=True)
R=R.drop_duplicates(['market','event_id','selection_id'])
R['ts']=pd.to_datetime(R.event_dt); md={m:x.ts.median() for m,x in R.groupby('market')}
out=[]
def tab(x,v,market,kind,q,band):
    h=(x.ts<md[market]).values; a,b=v[h],v[~h]; g=x.event_id.values; tr=tgame(v,g)
    return dict(market=market,kind=kind,q=q,band=band,n=len(v),races=x.event_id.nunique(),per10=v.mean(),t=tstat(v),tr=tr,n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,won=(x.win_lose==1).mean(),maxwin=v.max(),PASS=passes(len(v),len(a),len(b),tr,a.mean() if len(a) else 0,b.mean() if len(b) else 0,v.mean()))
for market,M in R.groupby('market'):
    for lo,hi,bn in BANDS:
        X=M[(M.bsp>lo)&(M.bsp<=hi)]
        for q in (1.05,1.1,1.2,1.3,1.5,2,3,5):
            x=X[(X.bsp>q)&lay_fill(X.ipmin.fillna(1e9),q)]
            if len(x)>=30: out.append(tab(x,pnl_lay(lay_px(np.full(len(x),float(q))),x.win_lose.values),market,'LAY',q,bn))
        for f in (.75,.5,.33,.2):
            tg=np.maximum(on_ladder(X.bsp.values*f),1.02); k=lay_fill(X.ipmin.fillna(1e9).values,tg); x=X[k]
            if len(x)>=30: out.append(tab(x,pnl_lay(lay_px(tg[k]),x.win_lose.values),market,'LAYxBSP',f,bn))
        for q in (5,10,20,50,100,200,500):
            x=X[(X.bsp<q)&back_fill(X.ipmax.fillna(0),q)]
            if len(x)>=30: out.append(tab(x,pnl_back(back_px(np.full(len(x),float(q))),x.win_lose.values),market,'BACK',q,bn))
        for f in (1.5,2,3,5,10):
            tg=on_ladder(np.minimum(X.bsp.values*f,1000)); k=back_fill(X.ipmax.fillna(0).values,tg)&(tg<1000); x=X[k]
            if len(x)>=30: out.append(tab(x,pnl_back(back_px(tg[k]),x.win_lose.values),market,'BACKxBSP',f,bn))
O=pd.DataFrame(out).sort_values('tr',ascending=False)
print(f"\n== ITEM 372: {len(O)} lines, top 30 by t per race\n",O.head(30).round(3).to_string(index=False),flush=True)
print("\n== bottom 12, the other side of these may be a clue, not a trade\n",O.tail(12).round(3).to_string(index=False))
print("\n== ALL band only, every level\n",O[O.band=='ALL'].sort_values(['market','kind','q']).round(3).to_string(index=False))
Z=O[O.PASS==True]; print(f"\n== SURVIVORS: {len(Z)} of {len(O)}\n",Z.round(3).to_string(index=False) if len(Z) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
