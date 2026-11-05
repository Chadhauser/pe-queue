#!/bin/bash
set -o pipefail
# 499_meeting_today (Finder 2026-11-05, queue item 116, Finder's own, source c): are earlier results at the same meeting today priced at BSP? Rule written in the queue before any price was read. The number 499 is reused with a new slug: 450-499 are all taken.
# DATA racing_bsp win markets, UK/IE. A race is used only if every runner has a BSP and a ppwap and the 1/ppwap book is 1.00-1.40, as jobs/499_racing_money_share.sh. Favourite = lowest ppwap; a tie is no favourite, so that race gives no favourite line and no favourite history.
# STATE from races at the same meeting (menu_hint and date) that went off at least 15 minutes earlier, so the result is known. The box holds part of each year's racing, so "earlier" means earlier ON THE BOX: read the states as noisy.
# ENTRY BSP, one tick adverse, 2% on profit, £10 risk, to result, nothing dropped; dead heats as jobs/499_racing_money_share.sh. Bands on ppwap, never on BSP of the race traded. A pass is an upper bound: ppwap runs to the off.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
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
def states(prior):
    """prior: earlier races at the meeting, oldest first, each (fav_won or None for no favourite, winner_bsp or None). Returns the list of state names."""
    if not prior: return []
    favs=[p[0] for p in prior if p[0] is not None]; wins=[p[1] for p in prior if p[1] is not None]; o=[]
    if len(prior)>=2: o.append('CTRL')
    if len(favs)>=2 and all(favs): o.append('FAVS_ALL_WON')
    if len(favs)>=3 and not any(favs): o.append('FAVS_NONE_3')
    if len(favs)>=5 and not any(favs): o.append('FAVS_NONE_5')
    if prior[-1][0] is True: o.append('LAST_FAV_WON')
    if prior[-1][0] is False: o.append('LAST_FAV_LOST')
    if prior[-1][1] is not None and prior[-1][1]>=16: o.append('SHOCK_LAST')
    if sum(w>=16 for w in wins)>=2: o.append('SHOCK2')
    if len(prior)>=2 and all(p[1] is not None and p[1]<=4 for p in prior[-2:]): o.append('CHALK2')
    return o
BANDS=[(3,6,'B3-6'),(6,12,'B6-12'),(12,30,'B12-30'),(30,1e9,'B30+')]
def leg(p,isfav):
    if isfav: return 'FAV'
    for lo,hi,n in BANDS:
        if lo<p<=hi: return n
    return None
# known answers, worked by hand
assert back_px(11.2)==11.0 and lay_px(11.2)==11.5 and back_px(2.0)==1.99 and lay_px(2.0)==2.02
assert abs(pnl_back(3.0,1)-19.6)<1e-9 and pnl_back(3.0,0)==-10 and abs(pnl_back(3.0,2)-4.9)<1e-9
assert abs(pnl_lay(3.0,0)-4.9)<1e-9 and pnl_lay(3.0,1)==-10 and pnl_lay(3.0,2)==-2.5
assert states([])==[] and states([(True,3.0)])==['LAST_FAV_WON']
assert states([(True,3.0),(True,2.5)])==['CTRL','FAVS_ALL_WON','LAST_FAV_WON','CHALK2']
assert states([(False,20.),(False,5.),(False,17.)])==['CTRL','FAVS_NONE_3','LAST_FAV_LOST','SHOCK_LAST','SHOCK2']
assert 'FAVS_NONE_5' in states([(False,5.)]*5) and 'FAVS_NONE_5' not in states([(False,5.)]*4)
assert states([(None,None),(None,3.0)])==['CTRL']     # no favourite history, one winner known: no favourite state, and CHALK2 needs both
assert leg(2.0,True)=='FAV' and leg(2.0,False) is None and leg(3.0,False) is None and leg(3.01,False)=='B3-6' and leg(30.,False)=='B12-30' and leg(30.5,False)=='B30+'
print("checks: OK",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
R=pd.read_sql("SELECT country,event_id,menu_hint,event_dt,selection_id,win_lose,bsp::float bsp,ppwap::float ppwap FROM racing_bsp WHERE market='win'",con); con.close()
print(f"win rows {len(R)}, races {R.event_id.nunique()}, {R.event_dt.min()} to {R.event_dt.max()}; countries {R.country.value_counts().to_dict()}; {time.time()-T0:.0f}s",flush=True)
R=R[R.country.str.lower().isin(['uk','ire','gb'])]
bad=R.bsp.isna()|(R.bsp<=1)|R.ppwap.isna()|(R.ppwap<=1)|R.win_lose.isna()
W=R[~R.event_id.isin(set(R.event_id[bad]))].copy()
bk_=(1/W.ppwap).groupby(W.event_id).sum(); ok=bk_[(bk_>=1.0)&(bk_<=1.40)].index; W=W[W.event_id.isin(ok)].copy()
W['day']=pd.to_datetime(W.event_dt).dt.date; W['mkey']=W.menu_hint.astype(str)+'|'+W.day.astype(str)
print(f"races used {W.event_id.nunique()} of {R.event_id.nunique()}, runners {len(W)}, meetings {W.mkey.nunique()}; {time.time()-T0:.0f}s",flush=True)
INFO={}
for e,x in W.groupby('event_id'):
    m=x.ppwap.values; f=m.min(); fav=x.selection_id.values[m.argmin()] if (m==f).sum()==1 else None
    fw=None if fav is None else bool(x.win_lose.values[m.argmin()]>=1)
    w=x.bsp.values[x.win_lose.values>=1]; INFO[e]=(fav,fw,float(w.max()) if len(w) else None)
# chain check: exactly one winner in most races, or the win_lose flag is not what this job assumes
print("races by winner count:",pd.Series(W.groupby('event_id').win_lose.apply(lambda v:(v>=1).sum())).value_counts().head(4).to_dict(),flush=True)
ST={}
for k,x in W.drop_duplicates('event_id').sort_values('event_dt').groupby('mkey'):
    ids=x.event_id.values; ts=pd.to_datetime(x.event_dt).values
    for i in range(len(ids)):
        pr=[(INFO[ids[j]][1],INFO[ids[j]][2]) for j in range(i) if (ts[i]-ts[j])/np.timedelta64(1,'m')>=15]
        ST[ids[i]]=states(pr)
W['isfav']=W.selection_id.values==W.event_id.map(lambda e:INFO[e][0]).values
W['leg']=[leg(p,f) for p,f in zip(W.ppwap.values,W.isfav.values)]
W=W[W['leg'].notna()].copy()
W['bk']=pnl_back(back_px(W.bsp.values),W.win_lose.values); W['ly']=pnl_lay(lay_px(W.bsp.values),W.win_lose.values)
med=W.event_dt.median(); W['h']=np.where(W.event_dt<med,1,2)
rows=[]
ev=W.event_id.values; S=[ST.get(e,[]) for e in ev]
X=[(st,i) for i,l in enumerate(S) for st in l]
L=pd.DataFrame(X,columns=['st','i']); L['leg']=W['leg'].values[L.i]; L['ev']=ev[L.i]; L['h']=W.h.values[L.i]; L['bk']=W.bk.values[L.i]; L['ly']=W.ly.values[L.i]; L['won']=(W.win_lose.values[L.i]>=1); L['imp']=1/W.ppwap.values[L.i]
out=[]
for (st,lg),d in L.groupby(['st','leg']):
    for side,c in (('BACK','bk'),('LAY','ly')):
        v=d[c].values; a=v[d.h.values==1]; b=v[d.h.values==2]; tr=tstat(d.groupby('ev')[c].sum().values)
        P=passes(len(v),len(a),len(b),tstat(v),a.mean() if len(a) else -1,b.mean() if len(b) else -1,v.mean()) and tr>=3.5
        out.append(dict(state=st,leg=lg,side=side,n=len(v),races=d.ev.nunique(),per10=v.mean(),t=tstat(v),t_race=tr,n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,won=d.won.mean(),imp=d.imp.mean(),maxwin=v.max(),PASS=P))
O=pd.DataFrame(out); print(f"\nlines {len(O)}, n>=300 {(O.n>=300).sum()}, median date {med}")
print("\n== TOP 15 by t, n>=150\n",O[O.n>=150].sort_values('t',ascending=False).head(15).round(3).to_string(index=False))
print("\n== BOTTOM 6 by t, n>=150\n",O[O.n>=150].sort_values('t').head(6).round(3).to_string(index=False))
print("\n== CONTROL, each leg\n",O[O.state=='CTRL'].round(3).to_string(index=False))
print("\n== state minus control, favourite\n")
c=O[(O.state=='CTRL')&(O.leg=='FAV')].set_index('side').per10
print(O[O.leg=='FAV'].assign(v_ctrl=lambda d:d.per10-d.side.map(c)).sort_values(['side','state'])[['state','side','n','per10','v_ctrl','t','won','imp']].round(3).to_string(index=False))
Y=O[O.PASS]; print(f"\n== SURVIVORS: {len(Y)} of {len(O)}\n",Y.round(3).to_string(index=False) if len(Y) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
