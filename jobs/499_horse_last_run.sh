#!/bin/bash
set -o pipefail
# 499_horse_last_run (Finder 2026-11-04, queue item 81, Finder's own, source d): is a horse's previous run priced into today's BSP? Rule written in the queue before any price was read. The number 499 is reused with a new slug: 450-499 are all taken.
# DATA racing_bsp only, UK/IE, 31 Dec 2021 to 12 Oct 2026. History by selection_id in WIN markets (one name per id checked in the census). Previous run = latest WIN market on an earlier date, so a horse's own earlier race that day is never history.
# LIMIT found on the first run: the box holds about 2,000-3,000 win races a year and only 45.1% of place runners have a win row for the same race, so "previous run" is the previous run ON THE BOX and the states are noisy. A fail here is not a fail of the idea: item 85.
# ENTRY BSP, which is a real fill for an SP bet placed before the off. One tick adverse on the Betfair ladder: BSP is off-ladder, so back takes the ladder price below it and lay the one above. 2% commission on profit, £10 risk, to result; nothing dropped.
# DEAD HEAT win_lose = 2: half the stake wins, half loses, treated as a two-way dead heat.
# BANDS on today's morning WAP, known before the off, never on the BSP traded. t_race is by race, as runners in one race are correlated.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import LD,tstat,passes
import lib_cand; lib_cand._checks()
pd.set_option('display.width',250); pd.set_option('display.max_rows',300); pd.set_option('display.max_columns',40)
T0=time.time()
def back_px(p):
    """Ladder price strictly below p."""
    p=np.asarray(p,dtype=float); return LD[np.clip(np.searchsorted(LD,p-1e-9,side='left')-1,0,len(LD)-1)]
def lay_px(p):
    """Ladder price strictly above p."""
    p=np.asarray(p,dtype=float); return LD[np.clip(np.searchsorted(LD,p+1e-9,side='right'),0,len(LD)-1)]
def pnl_back(a,wl):
    """£10 back at a. wl 1 won, 0 lost, 2 dead heat (half at full odds, half lost). 2% on a net win."""
    a=np.asarray(a,dtype=float); wl=np.asarray(wl); g=np.where(wl==1,10*(a-1),np.where(wl==2,5*(a-1)-5,-10.0))
    return np.where(g>0,g*.98,g)
def pnl_lay(a,wl):
    """£10 liability lay at a, stake 10/(a-1). Dead heat: lose half the liability, keep half the stake."""
    a=np.asarray(a,dtype=float); wl=np.asarray(wl); s=10/(a-1); g=np.where(wl==1,-10.0,np.where(wl==2,-5+s/2,s))
    return np.where(g>0,g*.98,g)
def add_history(W):
    """W: one row per runner per WIN market. Adds the previous run's fields from an EARLIER date, days since, and losses running. Sorted within the function."""
    W=W.sort_values(['selection_id','day','event_id']).reset_index(drop=True)
    out={k:[None]*len(W) for k in ('p_bsp','p_mw','p_wl','p_ipmin','p_day','losers')}
    sid=W.selection_id.values; day=W.day.values; wl=W.win_lose.values; bsp=W.bsp.values; mw=W.morningwap.values; ip=W.ipmin.values
    i=0; n=len(W)
    while i<n:
        j=i
        while j<n and sid[j]==sid[i]: j+=1
        last=None; run=0; k=i
        while k<j:
            m=k
            while m<j and day[m]==day[k]: m+=1
            for q in range(k,m):
                if last is not None:
                    out['p_bsp'][q],out['p_mw'][q],out['p_wl'][q],out['p_ipmin'][q],out['p_day'][q]=bsp[last],mw[last],wl[last],ip[last],day[last]
                    out['losers'][q]=run
            for q in range(k,m):
                run=0 if wl[q]==1 else run+1
                last=q
            k=m
        i=j
    for k,v in out.items(): W[k]=pd.array(v,dtype=object) if k=='p_day' else pd.to_numeric(pd.Series(v),errors='coerce').values
    return W
def states(W):
    """Dict of boolean masks. Uses today's morning WAP and fields from earlier dates only, never today's BSP or result."""
    has=W.p_bsp.notna(); won=W.p_wl==1; lost=W.p_wl==0
    gap=(pd.to_datetime(W.day)-pd.to_datetime(W.p_day)).dt.days; ip=W.p_ipmin.where(W.p_ipmin>=1.01)
    return {'CONTROL':has,'LTO_WON':has&won,'LTO_WON_BIG':has&won&(W.p_bsp>=10),'LTO_BEATEN_SHORT':has&lost&(W.p_bsp<=3),
        'LTO_TRADED_1.5':has&lost&(ip<=1.5),'LTO_TRADED_1.2':has&lost&(ip<=1.2),
        'LTO_GAMBLE_LOST':has&lost&(W.p_mw/W.p_bsp>=1.5),'LTO_DRIFT_WON':has&won&(W.p_bsp/W.p_mw>=1.5),
        'QUICK':has&(gap<=7),'LAYOFF':has&(gap>=90),'PRICE_IN':has&(W.morningwap<=.5*W.p_bsp),'PRICE_OUT':has&(W.morningwap>=2*W.p_bsp),'LOSERS10':has&(W.losers>=10)}
# known answers
assert back_px(11.2)==11.0 and lay_px(11.2)==11.5 and back_px(2.0)==1.99 and lay_px(2.0)==2.02 and back_px(3.0)==2.98 and lay_px(3.0)==3.05
assert abs(pnl_back(3.0,1)-19.6)<1e-9 and pnl_back(3.0,0)==-10 and abs(pnl_back(3.0,2)-4.9)<1e-9 and pnl_back(2.0,2)==0 and abs(pnl_back(5.0,2)-(5*4-5)*.98)<1e-9 and pnl_back(1.5,2)==-2.5
assert abs(pnl_lay(3.0,0)-4.9)<1e-9 and pnl_lay(3.0,1)==-10 and pnl_lay(3.0,2)==-2.5 and pnl_lay(5.0,2)==-3.75
_d=lambda s:pd.Timestamp(s).date()
_W=pd.DataFrame([dict(selection_id=7,day=_d('2024-01-01'),event_id=1,win_lose=0,bsp=2.5,morningwap=4.0,ipmin=1.1),
    dict(selection_id=7,day=_d('2024-01-05'),event_id=2,win_lose=1,bsp=12.,morningwap=6.,ipmin=1.01),
    dict(selection_id=7,day=_d('2024-01-05'),event_id=3,win_lose=0,bsp=9.,morningwap=9.,ipmin=5.),      # second race that day: history is still 1 Jan
    dict(selection_id=7,day=_d('2024-06-01'),event_id=4,win_lose=0,bsp=8.,morningwap=30.,ipmin=5.),
    dict(selection_id=8,day=_d('2024-01-05'),event_id=2,win_lose=0,bsp=5.,morningwap=5.,ipmin=2.)])
_H=add_history(_W); _S=states(_H); _x=_H[(_H.selection_id==7)]
assert np.isnan(_x.p_bsp.iloc[0]) and list(_x.p_bsp.iloc[1:3])==[2.5,2.5] and _x.p_bsp.iloc[3]==9. and _x.losers.iloc[3]==1
assert np.isnan(_H[_H.selection_id==8].p_bsp.iloc[0])                                                  # another horse's history never leaks
_m=lambda k:list(_S[k][_H.selection_id==7])
assert _m('LTO_BEATEN_SHORT')==[False,True,True,False] and _m('LTO_TRADED_1.2')==[False,True,True,False] and _m('LTO_GAMBLE_LOST')==[False,True,True,False]
assert _m('LAYOFF')==[False,False,False,True] and _m('QUICK')==[False,True,True,False] and _m('PRICE_OUT')==[False,True,True,True] and _m('LTO_WON')==[False,False,False,False]
print("checks: OK",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
R=pd.read_sql("SELECT market,event_id,event_dt,selection_id,win_lose,bsp::float bsp,morningwap::float morningwap,ipmin::float ipmin FROM racing_bsp WHERE bsp IS NOT NULL AND bsp>1",con); con.close()
R['day']=pd.to_datetime(R.event_dt,utc=True).dt.tz_convert('Europe/London').dt.date
W=R[R.market=='win'].copy(); PL=R[R.market=='place'].copy()
print(f"win runners {len(W)} races {W.event_id.nunique()}; place runners {len(PL)} races {PL.event_id.nunique()}; {W.day.min()} to {W.day.max()}; dead heat rows win {(W.win_lose==2).sum()} place {(PL.win_lose==2).sum()}; {time.time()-T0:.0f}s",flush=True)
# COVERAGE racing_bsp is a part of each year's racing and its win and place markets are often different races, so "previous run" is the previous run ON THE BOX, not always the real last run.
_c=R.assign(y=pd.to_datetime(R.day).dt.year,k=R.event_dt.astype(str)+R.market).groupby(['y','market']).event_id.nunique().unstack(); _rw=set(zip(W.event_dt,W.selection_id)); _rp=set(zip(PL.event_dt,PL.selection_id))
print("races a year on the box\n"+_c.to_string()+f"\nplace runners with a win row for the same race and horse {len(_rw&_rp)/len(_rp):.3f}",flush=True)
W=add_history(W); S=states(W); print(f"history built, with a previous run {W.p_bsp.notna().mean():.3f}, {time.time()-T0:.0f}s",flush=True)
W['key']=W.selection_id.astype(str)+'|'+W.day.astype(str)
# one place row per selection-day; a horse twice in one day (census: 10 cases) is dropped from PLACE, as the win race cannot be told apart
PL['key']=PL.selection_id.astype(str)+'|'+PL.day.astype(str); dup=PL.key.duplicated(keep=False)|PL.key.isin(W.key[W.key.duplicated(keep=False)]); print(f"place rows dropped as a horse ran twice that day {int(dup.sum())}",flush=True); PL=PL[~dup]
med=W.day.sort_values().iloc[len(W)//2]; print(f"halves split at {med}",flush=True)
BANDS={'all':lambda m:m>0,'<=5':lambda m:(m>0)&(m<=5),'5-15':lambda m:(m>5)&(m<=15),'>15':lambda m:m>15}
rows=[]; X={}
for mk,src in (('WIN',W),('PLACE',PL)):
    for st,mask in S.items():
        base=W[mask]
        if mk=='WIN': d=base
        else:
            d=PL.merge(base[['key','morningwap']].rename(columns={'morningwap':'mw_win'}),on='key')
            d['morningwap']=d.mw_win    # bands stay on the WIN morning price in both markets
        for b,fn in BANDS.items():
            x=d[fn(d.morningwap)]
            if len(x)<30: continue
            for side in ('BACK','LAY'):
                a=back_px(x.bsp.values) if side=='BACK' else lay_px(x.bsp.values)
                keep=a>1.01; y=x[keep]; a=a[keep]
                v=pnl_back(a,y.win_lose.values) if side=='BACK' else pnl_lay(a,y.win_lose.values)
                h=(y.day.values<=med); by=pd.Series(v).groupby(y.event_id.values).sum()
                n1,n2=int(h.sum()),int((~h).sum()); m1=v[h].mean() if n1 else np.nan; m2=v[~h].mean() if n2 else np.nan
                raw=pnl_back(y.bsp.values,y.win_lose.values) if side=='BACK' else pnl_lay(y.bsp.values,y.win_lose.values)
                t=tstat(v); tr=tstat(by.values)
                rows.append(dict(mkt=mk,state=st,band=b,side=side,n=len(v),races=len(by),per10=round(v.mean(),3),exact_bsp=round(raw.mean(),3),t=round(t,2),t_race=round(tr,2),h1=round(m1,3),h2=round(m2,3),PASS=passes(len(v),n1,n2,t,m1,m2,v.mean()) and tr>=3.5))
                X[(mk,st,b,side)]=(y.day.values,v,y.event_id.values)
    print(f"  {mk} done {time.time()-T0:.0f}s",flush=True)
L=pd.DataFrame(rows); E=L[L.n>=300].sort_values('t',ascending=False)
print(f"\nlines {len(L)}, at n>=300 {len(E)}, positive after costs {(E.per10>0).sum()}, passing {int(L.PASS.sum())}; PASS needs n>=300, 150 a half, both halves>0, mean>=0.15, t and t by race >=3.5")
print("\nCONTROL (base rate for reading each market)"); print(L[(L.state=='CONTROL')].to_string(index=False))
print("\nTOP 25 by t, n>=300"); print(E.head(25).to_string(index=False))
print("\nBOTTOM 8 by t, n>=300"); print(E.tail(8).to_string(index=False))
print("\nSURVIVORS")
P=L[L.PASS]
if not len(P): print("none")
for _,r in P.iterrows():
    d,v,e=X[(r.mkt,r.state,r.band,r.side)]; yr=pd.Series(v).groupby(pd.to_datetime(d).year).agg(['count','mean']).round(3)
    print(r.to_dict()); print(yr.T.to_string())
print(f"done {time.time()-T0:.0f}s")
PY
