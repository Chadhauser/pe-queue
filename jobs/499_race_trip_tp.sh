#!/bin/bash
set -o pipefail
# 499_race_trip_tp (Finder 2026-11-08, queue item 466, Finder's own, source c): in-play take-profit after a BSP entry, cut by race code and trip, a cut item 3 never read. Rule written in the queue (commit 461f57e) before any price was read. Costs and dead heats from jobs/499_race_shape.sh. 450-499 are all taken, so 499 is reused with a new slug.
# DATA racing_bsp win and place, UK/IE, BSP > 1.01 and a result. CODE from event_name (Chs CHASE, Hrd HURDLE, NHF/INHF/Bumper NHF, else FLAT); TRIP in furlongs from the name; names with no trip counted, not traded.
# ENTRY BSP one tick adverse. BACK_TP k: resting lay at L = ladder at or under BSP*k, fills only if ipmin < L (traded through), priced one tick worse than L. LAY_TP k: resting back at H = ladder at or over BSP*k, fills only if ipmax > H, priced one tick worse. Unfilled: held to result. 2% on profit, GBP 10 risk.
# A runner with no in-play trade (ipmin or ipmax null) is NOT dropped: its resting order simply never fills (tighter than the queue text, which named runners with ipmin and ipmax; dropping them would use the future).
# LIMIT ipmin/ipmax have no time, so a pass is an upper bound and needs the in-play touch before it counts. Many runners per race: the bar also needs t clustered by race >= 3.5.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,time,re,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import LD,tstat,passes
import lib_cand; lib_cand._checks()
pd.set_option('display.width',250); pd.set_option('display.max_rows',300); pd.set_option('display.max_columns',40)
T0=time.time()
def back_px(p):
    p=np.asarray(p,dtype=float); return LD[np.clip(np.searchsorted(LD,p-1e-9,side='left')-1,0,len(LD)-1)]
def lay_px(p):
    p=np.asarray(p,dtype=float); return LD[np.clip(np.searchsorted(LD,p+1e-9,side='right'),0,len(LD)-1)]
def floor_ld(x):
    x=np.asarray(x,dtype=float); i=np.searchsorted(LD,x+1e-9,side='right')-1; return np.where(i>=0,LD[np.clip(i,0,len(LD)-1)],np.nan)
def ceil_ld(x):
    x=np.asarray(x,dtype=float); i=np.searchsorted(LD,x-1e-9,side='left'); return np.where(i<len(LD),LD[np.clip(i,0,len(LD)-1)],np.nan)
def com(g): return np.where(g>0,g*.98,g)
def pnl_back(a,wl):
    a=np.asarray(a,dtype=float); wl=np.asarray(wl); return com(np.where(wl==1,10*(a-1),np.where(wl==2,5*(a-1)-5,-10.0)))
def pnl_lay(a,wl):
    a=np.asarray(a,dtype=float); wl=np.asarray(wl); s=10/(a-1); return com(np.where(wl==1,-10.0,np.where(wl==2,-5+s/2,s)))
def back_tp(bsp,ipmin,wl,k):
    """back at BSP one tick adverse; resting lay at floor(BSP*k), fills if ipmin < L, priced one tick up. Returns pnl, valid, filled."""
    A=back_px(bsp); L=floor_ld(np.asarray(bsp,float)*k); Lp=lay_px(L)
    valid=(~np.isnan(L))&(L>=1.01)&(Lp<A)&(A>1.01)
    filled=valid&(np.nan_to_num(np.asarray(ipmin,float),nan=1e9)<L)
    Ls=np.where(valid,Lp,2.0); green=com(10*A/Ls-10)
    return np.where(filled,green,pnl_back(A,wl)),valid,filled
def lay_tp(bsp,ipmax,wl,k):
    """lay at BSP one tick adverse, GBP 10 liability; resting back at ceil(BSP*k), fills if ipmax > H, priced one tick down."""
    A=lay_px(bsp); H=ceil_ld(np.asarray(bsp,float)*k); Hp=back_px(H)
    valid=(~np.isnan(H))&(H<1000)&(Hp>A)&(A>1.01)
    filled=valid&(np.nan_to_num(np.asarray(ipmax,float),nan=-1)>H)
    s=10/(A-1); Hs=np.where(valid,Hp,2*A); green=com(s*(1-A/Hs))
    return np.where(filled,green,pnl_lay(A,wl)),valid,filled
RX=re.compile(r'^\s*(?:(\d)m)?\s*(?:(\d{1,2})\D?f)?')
def trip_f(name):
    m=RX.match(str(name));
    if not m or (m.group(1) is None and m.group(2) is None): return np.nan
    return 8*int(m.group(1) or 0)+int(m.group(2) or 0)
def code_of(name):
    s=str(name)
    if re.search(r'\bChs\b|Chase',s): return 'CHASE'
    if re.search(r'\bHrd\b|Hurdle',s): return 'HURDLE'
    if re.search(r'\bI?NHF\b|Bumper',s,re.I): return 'NHF'
    return 'FLAT'
def trip_band(code,f):
    if np.isnan(f): return None
    if code=='FLAT': return 'SPRINT' if f<=6 else ('MILE' if f<=10 else 'STAY')
    return 'SHORT' if f<=18 else ('MID' if f<=23 else 'LONG')
# known answers, worked by hand
assert trip_f('2m4f Hcap Chs')==20 and trip_f('6f Nov Stks')==6 and trip_f('1m2f Hcap')==10 and trip_f('3m Hcap Chs')==24 and trip_f('2m1f INHF')==17 and np.isnan(trip_f('Hcap Chs'))
assert code_of('2m4f Hcap Chs')=='CHASE' and code_of('2m Hcap Hrd')=='HURDLE' and code_of('2m1f INHF')=='NHF' and code_of('5f Grp 2')=='FLAT'
assert trip_band('FLAT',6)=='SPRINT' and trip_band('FLAT',7)=='MILE' and trip_band('FLAT',12)=='STAY' and trip_band('CHASE',24)=='LONG' and trip_band('HURDLE',18)=='SHORT' and trip_band('NHF',20)=='MID'
assert floor_ld(5.0)==5.0 and floor_ld(5.05)==5.0 and ceil_ld(5.05)==5.1 and back_px(10.0)==9.8 and lay_px(5.0)==5.1
# BACK_TP: BSP 10 -> A 9.8; k .5 -> L 5.0, priced 5.1; green 10*9.8/5.1-10 = 9.2157, x .98 = 9.0314
p,v,f=back_tp([10.0],[4.0],[0],0.5); assert v[0] and f[0] and abs(p[0]-(10*9.8/5.1-10)*.98)<1e-9
p,v,f=back_tp([10.0],[5.0],[1],0.5); assert v[0] and not f[0] and abs(p[0]-10*8.8*.98)<1e-9     # ipmin == L: not traded through, held, won
p,v,f=back_tp([10.0],[np.nan],[0],0.5); assert v[0] and not f[0] and p[0]==-10                       # never traded in play: held, lost
p,v,f=back_tp([1.5],[1.01],[1],0.67); assert not v[0]                                                # 1.5*.67=1.005 under the ladder: no trade
# LAY_TP: BSP 10 -> A 10.5, s 10/9.5; k 2 -> H 20, priced 19.5; green s*(1-10.5/19.5) = 0.48583, x .98
p,v,f=lay_tp([10.0],[25.0],[1],2.0); s=10/9.5; assert v[0] and f[0] and abs(p[0]-s*(1-10.5/19.5)*.98)<1e-9
p,v,f=lay_tp([10.0],[20.0],[1],2.0); assert v[0] and not f[0] and p[0]==-10
p,v,f=lay_tp([10.0],[20.0],[0],2.0); assert abs(p[0]-s*.98)<1e-9
p,v,f=lay_tp([500.0],[1000.0],[0],3.0); assert not v[0]                                              # H would be over 1000
print("checks: OK",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
R=pd.read_sql("SELECT country,market,event_id,event_name,menu_hint,event_dt,selection_id,win_lose,bsp::float bsp,ipmin::float ipmin,ipmax::float ipmax FROM racing_bsp WHERE market IN ('win','place')",con); con.close()
print(f"rows {len(R)}, races {R.event_id.nunique()}, by market {R.market.value_counts().to_dict()}, by country {R.country.value_counts().to_dict()}; {time.time()-T0:.0f}s",flush=True)
n0=len(R); R=R[R.country.isin(['uk','ire'])&R.bsp.notna()&(R.bsp>1.01)&R.win_lose.isin([0,1,2])].copy()
print(f"kept {len(R)} of {n0} (UK/IE, BSP>1.01, result 0/1/2); ipmin null {R.ipmin.isna().sum()}, ipmax null {R.ipmax.isna().sum()} (kept, never fill)",flush=True)
# FIX (re-run 1): place markets are named 'To Be Placed', so they take the race name of the win market at the same course and off time
wn=R[R.market=='win'].drop_duplicates('event_id').groupby(['menu_hint','event_dt']).event_name.first()
names=R[['event_id','event_name','market','menu_hint','event_dt']].drop_duplicates('event_id').copy()
pl=names.market=='place'; key=pd.MultiIndex.from_frame(names.loc[pl,['menu_hint','event_dt']])
names.loc[pl,'event_name']=wn.reindex(key).values
print(f"place markets {int(pl.sum())}, matched to a win race {int(names.loc[pl,'event_name'].notna().sum())}",flush=True)
names=names[['event_id','event_name']]
names['code']=names.event_name.map(code_of); names['f']=names.event_name.map(trip_f); names['trip']=[trip_band(c,f) for c,f in zip(names.code,names.f)]
print("races by code and trip:\n",names.groupby(['code','trip'],dropna=False).size().to_string(),flush=True)
print(f"no trip in name: {names.trip.isna().sum()} races, e.g. {names[names.trip.isna()].event_name.head(5).tolist()}",flush=True)
R=R.merge(names[['event_id','code','trip']],on='event_id'); R=R[R.trip.notna()]
R['day']=pd.to_datetime(R.event_dt).dt.date; med=R.day.sort_values().iloc[len(R)//2]
R['band']=pd.cut(R.bsp,[1.01,3,6,12,30,1e9],labels=['<=3','3-6','6-12','12-30','30+'],include_lowest=True).astype(str)
print(f"runners {len(R)}, races {R.event_id.nunique()}; halves split at {med}; {time.time()-T0:.0f}s",flush=True)
SH={}
for k in (0.67,0.5,0.33):
    p,v,f=back_tp(R.bsp.values,R.ipmin.values,R.win_lose.values,k); SH[f'BACK_TP{k}']=(p,v,f)
for k in (1.5,2.0,3.0):
    p,v,f=lay_tp(R.bsp.values,R.ipmax.values,R.win_lose.values,k); SH[f'LAY_TP{k}']=(p,v,f)
A=back_px(R.bsp.values); SH['BACK']=(pnl_back(A,R.win_lose.values),A>1.01,np.zeros(len(R),bool))
A=lay_px(R.bsp.values); SH['LAY']=(pnl_lay(A,R.win_lose.values),A>1.01,np.zeros(len(R),bool))
ev=R.event_id.values; h1=(R.day.values<=med); mk=R.market.values; cd=R.code.values; tr=R.trip.values; bd=R.band.values
rows=[]
cuts=[('code',None)]
for m in ('win','place'):
    for c in ('FLAT','HURDLE','CHASE','NHF','ALL'):
        trips=['ALL']+sorted(set(tr[cd==c])) if c!='ALL' else ['ALL']
        for t_ in trips:
            for b in ('ALL','<=3','3-6','6-12','12-30','30+'):
                base=(mk==m)&((cd==c) if c!='ALL' else True)&((tr==t_) if t_!='ALL' else True)&((bd==b) if b!='ALL' else True)
                for sh,(p,v,f) in SH.items():
                    sel=base&v
                    n=int(sel.sum())
                    if n<30: continue
                    x=p[sel]; hh=h1[sel]; n1,n2=int(hh.sum()),int((~hh).sum())
                    m1=x[hh].mean() if n1 else np.nan; m2=x[~hh].mean() if n2 else np.nan
                    by=pd.Series(x).groupby(ev[sel]).sum().values; t=tstat(x); trc=tstat(by)
                    rows.append(dict(mkt=m,code=c,trip=t_,band=b,shape=sh,n=n,races=len(by),fill=round(f[sel].mean(),3),per10=round(x.mean(),3),t=round(t,2),t_race=round(trc,2),h1=round(m1,3),h2=round(m2,3),
                                     PASS=passes(n,n1,n2,t,m1,m2,x.mean()) and trc>=3.5))
L=pd.DataFrame(rows); E=L[L.n>=300].sort_values('t',ascending=False)
print(f"\nlines {len(L)}, at n>=300 {len(E)}, positive {(E.per10>0).sum()}, passing {int(L.PASS.sum())}; PASS needs n>=300, 150 a half, both halves>0, mean>=0.15, t and t by race >=3.5; {time.time()-T0:.0f}s")
print("\nCONTROL (code ALL, band ALL)"); print(L[(L.code=='ALL')&(L.band=='ALL')].to_string(index=False))
print("\nBY CODE AND TRIP, band ALL, win"); print(L[(L.mkt=='win')&(L.band=='ALL')&(L.code!='ALL')].sort_values(['shape','code','trip']).to_string(index=False))
print("\nTOP 15 by t, n>=300"); print(E.head(15).to_string(index=False))
print("\nTOP 10 by t_race, n>=300"); print(E.sort_values('t_race',ascending=False).head(10).to_string(index=False))
print("\nBOTTOM 5 by t, n>=300"); print(E.tail(5).to_string(index=False))
print("\nSURVIVORS"); P=L[L.PASS]; print(P.to_string(index=False) if len(P) else "none")
print(f"done {time.time()-T0:.0f}s")
PY
