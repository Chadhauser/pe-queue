#!/bin/bash
set -o pipefail
# 499_race_shape (Finder 2026-11-05, queue item 90, Finder's own, source c): is the shape of a race priced at BSP? Rule written in the queue before any price was read. Costs and dead heats from jobs/499_horse_last_run.sh. The number 499 is reused with a new slug: 450-499 are all taken.
# DATA racing_bsp win markets only, UK/IE. A race is used only if every runner has a morning WAP and a ppwap and the 1/ppwap book is 1.00-1.40.
# ENTRY BSP, one tick adverse on the ladder, 2% commission on profit, £10 risk, to result; nothing dropped. Favourite and second are ranked on ppwap, never on BSP.
# LIMIT ppwap runs to the off, so a live rule needs the last minutes' average: read a pass as an upper bound. The box holds part of each year's racing, so LAST is the last race ON THE BOX and is noisy.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import LD,tstat,passes
import lib_cand; lib_cand._checks()
pd.set_option('display.width',250); pd.set_option('display.max_rows',300); pd.set_option('display.max_columns',40); pd.set_option('display.max_colwidth',60)
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
def shape(W):
    """One row per runner of complete races. Adds rank on pp and morning, race-level states."""
    W=W.copy()
    W['rp']=W.groupby('event_id').ppwap.rank(method='first'); W['rm']=W.groupby('event_id').morningwap.rank(method='first')
    g=W.groupby('event_id'); W['field']=g.selection_id.transform('size')
    p1=W[W.rp==1].set_index('event_id').ppwap; p2=W[W.rp==2].set_index('event_id').ppwap
    W['p1']=W.event_id.map(p1); W['p2']=W.event_id.map(p2)
    mfav=W[W.rm==1].set_index('event_id').selection_id; pfav=W[W.rp==1].set_index('event_id').selection_id
    W['mfav']=W.event_id.map(mfav); W['pfav']=W.event_id.map(pfav)
    W['flip']=W.mfav!=W.pfav
    return W
def targets(W):
    return {'FAV':W.rp==1,'SECOND':W.rp==2,'LONG30':W.ppwap>=30}
def race_states(W):
    return {'ALL':W.field>0,'NOFLIP':~W.flip,'HOT':(W.p1<=2)&(W.p2>=2*W.p1),'CLOSE':W.p2<=1.1*W.p1,'FIELD<=6':W.field<=6,'FIELD>=16':W.field>=16,
        'EVENING':W.hour>=17,'SATURDAY':W.dow==5,'MIDWEEK':W.dow.isin([0,1,2,3]),'LAST':W.last_race,
        'HCAP':W.event_name.str.contains('Hcap',case=False,na=False),'MDN_NOV':W.event_name.str.contains(r'Mdn|Nov',case=False,na=False,regex=True),'NHF':W.event_name.str.contains('NHF',case=False,na=False)}
# known answers, worked by hand
assert back_px(11.2)==11.0 and lay_px(11.2)==11.5 and back_px(2.0)==1.99 and lay_px(2.0)==2.02
assert abs(pnl_back(3.0,1)-19.6)<1e-9 and pnl_back(3.0,0)==-10 and abs(pnl_back(3.0,2)-4.9)<1e-9
assert abs(pnl_lay(3.0,0)-4.9)<1e-9 and pnl_lay(3.0,1)==-10 and pnl_lay(3.0,2)==-2.5
_W=pd.DataFrame([dict(event_id=1,selection_id=11,ppwap=2.0,morningwap=3.0),dict(event_id=1,selection_id=12,ppwap=2.1,morningwap=2.5),dict(event_id=1,selection_id=13,ppwap=40.,morningwap=30.),
                 dict(event_id=2,selection_id=21,ppwap=1.8,morningwap=1.9),dict(event_id=2,selection_id=22,ppwap=4.0,morningwap=4.0)])
_S=shape(_W); _T=targets(_S)
assert list(_S.flip)==[True,True,True,False,False] and list(_T['FAV'])==[True,False,False,True,False] and list(_T['SECOND'])==[False,True,False,False,True] and list(_T['LONG30'])==[False,False,True,False,False]
_S['hour']=[18]*5; _S['dow']=[5,5,5,1,1]; _S['last_race']=[False]*5; _S['event_name']=['2m Hcap']*3+['1m Mdn Stks']*2
_R=race_states(_S)
assert list(_R['CLOSE'])==[True]*3+[False]*2 and list(_R['HOT'])==[False]*3+[True]*2 and list(_R['NOFLIP'])==[False]*3+[True]*2 and list(_R['FIELD<=6'])==[True]*5 and list(_R['SATURDAY'])==[True]*3+[False]*2 and list(_R['HCAP'])==[True]*3+[False]*2 and list(_R['MDN_NOV'])==[False]*3+[True]*2
_F=_S[_S.flip]; assert _F[_F.selection_id==_F.mfav].selection_id.tolist()==[12] and _F[_F.selection_id==_F.pfav].selection_id.tolist()==[11]    # OLD is the morning favourite, NEW the pre-play one
print("checks: OK",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
R=pd.read_sql("SELECT event_id,event_name,menu_hint,event_dt,selection_id,win_lose,bsp::float bsp,ppwap::float ppwap,morningwap::float morningwap FROM racing_bsp WHERE market='win'",con); con.close()
print(f"win rows {len(R)}, races {R.event_id.nunique()}; sample names {R.event_name.drop_duplicates().sample(6,random_state=1).tolist()}; {time.time()-T0:.0f}s",flush=True)
bad=R.bsp.isna()|(R.bsp<=1)|R.ppwap.isna()|(R.ppwap<=1)|R.morningwap.isna()|(R.morningwap<=1)
ev_bad=set(R.event_id[bad]); W=R[~R.event_id.isin(ev_bad)].copy()
bk=(1/W.ppwap).groupby(W.event_id).sum(); ok=bk[(bk>=1.0)&(bk<=1.40)].index; W=W[W.event_id.isin(ok)]
print(f"races with every runner priced {len(bk)}; book 1.00-1.40 {len(ok)}, runners {len(W)}; quartiles {bk.quantile([.25,.5,.75]).round(3).tolist()}",flush=True)
dt=pd.to_datetime(W.event_dt,utc=True).dt.tz_convert('Europe/London'); W['day']=dt.dt.date; W['hour']=dt.dt.hour; W['dow']=dt.dt.dayofweek; W['ts']=dt
W['course']=W.menu_hint.astype(str).str.split(' ').str[0]
Rc=W.drop_duplicates('event_id')[['event_id','course','day','ts']].sort_values('ts'); Rc['cnt']=Rc.groupby(['course','day']).event_id.transform('size'); Rc['pos']=Rc.groupby(['course','day']).cumcount()+1
last=set(Rc[(Rc.cnt>=5)&(Rc.pos==Rc.cnt)].event_id); W['last_race']=W.event_id.isin(last); print(f"LAST races {len(last)}; event_dt counts per course-day median {Rc.groupby(['course','day']).size().median()}",flush=True)
W=shape(W); med=W.day.sort_values().iloc[len(W)//2]; print(f"halves split at {med}; flip races {W[W.flip].event_id.nunique()} of {W.event_id.nunique()}; {time.time()-T0:.0f}s",flush=True)
def add(rows,name,tg,x):
    if len(x)<30: return
    for side in ('BACK','LAY'):
        a=back_px(x.bsp.values) if side=='BACK' else lay_px(x.bsp.values)
        keep=a>1.01; y=x[keep]; a=a[keep]
        if len(y)<30: continue
        v=pnl_back(a,y.win_lose.values) if side=='BACK' else pnl_lay(a,y.win_lose.values)
        h=y.day.values<=med; by=pd.Series(v).groupby(y.event_id.values).sum(); n1,n2=int(h.sum()),int((~h).sum())
        m1=v[h].mean() if n1 else np.nan; m2=v[~h].mean() if n2 else np.nan; t=tstat(v); tr=tstat(by.values)
        rows.append(dict(state=name,target=tg,side=side,n=len(v),races=len(by),per10=round(v.mean(),3),t=round(t,2),t_race=round(tr,2),h1=round(m1,3),h2=round(m2,3),PASS=passes(len(v),n1,n2,t,m1,m2,v.mean()) and tr>=3.5))
rows=[]; TG=targets(W)
for st,mask in race_states(W).items():
    for tg,tm in TG.items(): add(rows,st,tg,W[mask&tm])
F=W[W.flip]; add(rows,'FLIP','OLD',F[F.selection_id==F.mfav]); add(rows,'FLIP','NEW',F[F.selection_id==F.pfav])
L=pd.DataFrame(rows); E=L[L.n>=300].sort_values('t',ascending=False)
print(f"\nlines {len(L)}, at n>=300 {len(E)}, positive {(E.per10>0).sum()}, passing {int(L.PASS.sum())}; PASS needs n>=300, 150 a half, both halves>0, mean>=0.15, t and t by race >=3.5")
print("\nCONTROL"); print(L[L.state=='ALL'].to_string(index=False))
print("\nFLIP"); print(L[L.state=='FLIP'].to_string(index=False))
print("\nTOP 15 by t, n>=300"); print(E.head(15).to_string(index=False))
print("\nBOTTOM 5 by t, n>=300"); print(E.tail(5).to_string(index=False))
print("\nSURVIVORS"); P=L[L.PASS]; print(P.to_string(index=False) if len(P) else "none")
print(f"done {time.time()-T0:.0f}s")
PY
