#!/bin/bash
set -o pipefail
# 499_let_off (Finder 2026-11-04, queue item 84, Finder's own, source a): is the price right after a missed penalty or a VAR reversal? Rule written in the queue before any price was read. Style from jobs/455_red_cards.sh. The number 499 is reused with a new slug: 450-499 are all taken.
# DATA af_events, af_fixtures, af_price_map, bf_hist_price (MO, OU25), seasons 2024 and 2025. One entry per game per event type per trade.
# ENTRY first real print in event +2..+4 (E2) or +5..+7 (E5), filled at the worse of it and the next print within 2 min, one tick adverse. No print in the window: no trade, never a forward fill.
# EXIT settle, or first print at +10 minutes or later to 95, one tick adverse; no print = settled at the result. Over 2.5: third goal by the exit minute = settled at the result, never dropped. 2% commission, £10 risk.
# OWN GOALS are not flipped (item 38): only the goal total is read, and results come from af_fixtures.
# LIMIT found on the first run: af_events holds 319 missed penalties on mapped 2024 games and 21 on 2025 games, against 1,205 and 1,374 penalty goals, so MISSED_PEN has almost no second half and cannot pass: item 86. VAR rows are even across seasons. is_home on a VAR row is taken as the team the call went against, not checked; TEAM and OPP are both run, so no verdict rests on it.
# CLOCK the tape clock can differ from the af minute (item 19), so an E2 print could predate the event. A line good at E2 and not E5 is read as look-ahead.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import defaultdict
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import *
import lib_cand; lib_cand._checks()
pd.set_option('display.width',250); pd.set_option('display.max_rows',300); pd.set_option('display.max_columns',40)
T0=time.time()
def first_print(arr,a,b):
    for m in range(max(a,0),min(b,95)+1):
        if arr[m]==arr[m]: return m
    return None
def fill(arr,m,side):
    """Worse of the print at m and the next print within 2 minutes: back takes the lower, lay the higher."""
    p=arr[m]
    for k in (m+1,m+2):
        if k<=95 and arr[k]==arr[k]:
            p=min(p,arr[k]) if side=='B' else max(p,arr[k]); break
    return float(p)
def trade(side,arr,c,lo,hi,won,exit10,goal_min=None):
    """P&L or None. c event minute; entry window c+lo..c+hi. goal_min: minute the Over market settles (third goal), or None. Over is settled at the result if that comes by the exit print."""
    d=first_print(arr,c+lo,c+hi)
    if d is None: return None
    a=step(fill(arr,d,side),-1 if side=='B' else 1)
    if side=='B' and a<=1.01: return None
    settle=back_settle(a,won) if side=='B' else lay_settle(a,won)
    if not exit10: return settle
    x=first_print(arr,d+10,95)
    if x is None or (goal_min is not None and goal_min<=x): return settle
    return back_hedge(a,float(arr[x])) if side=='B' else lay_hedge(a,float(arr[x]))
# known answers, prices worked by hand
_a=np.full(96,np.nan); _a[12]=2.0; _a[13]=2.1; _a[25]=3.0
assert first_print(_a,12,14)==12 and first_print(_a,14,16) is None and fill(_a,12,'B')==2.0 and fill(_a,12,'L')==2.1 and fill(_a,25,'L')==3.0
# Back: fill 2.0 -> 1.99. Win 9.702; lose -10; out at 3.0 -> lay 3.05: 10*(1.99/3.05-1) = -3.47541.
assert abs(trade('B',_a,10,2,4,True,False)-9.702)<1e-9 and trade('B',_a,10,2,4,False,False)==-10 and abs(trade('B',_a,10,2,4,False,True)+3.475410)<1e-5
# Lay: fill 2.1 -> 2.12, stake 8.928571. Selection loses +8.75; wins -10; out at 3.0 -> back 2.98: 8.928571*(1-2.12/2.98)*.98 = 2.525.
assert abs(trade('L',_a,10,2,4,False,False)-8.75)<1e-6 and trade('L',_a,10,2,4,True,False)==-10 and abs(trade('L',_a,10,2,4,False,True)-8.928571*(1-2.12/2.98)*.98)<1e-4
assert trade('B',_a,0,2,4,True,False) is None                                                       # no print in the window, no trade
assert abs(trade('B',_a,10,2,4,True,True,goal_min=20)-9.702)<1e-9                                     # third goal before the exit print: settled, a win
_b=np.full(96,np.nan); _b[12]=2.0; assert abs(trade('B',_b,10,2,4,True,True)-9.702)<1e-9            # no exit print: settled at the result
print("checks: OK",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
G=pd.read_sql("""SELECT m.event_id,f.fixture_id,f.season,f.hg,f.ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL AND f.season IN (2024,2025)""",con)
ids=list(map(int,G.fixture_id))
EV=pd.read_sql("SELECT fixture_id,coalesce(minute,0) AS minute,is_home,type,detail FROM af_events WHERE fixture_id=ANY(%s) AND ((type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal','Missed Penalty')) OR (type='Var' AND detail IN ('Goal cancelled','Penalty cancelled')))",con,params=(ids,))
NAME={'Missed Penalty':'MISSED_PEN','Goal cancelled':'VAR_GOAL_OFF','Penalty cancelled':'VAR_PEN_OFF'}
goals=defaultdict(list); X=[]
for r in EV.itertuples():
    if r.type=='Goal' and r.detail!='Missed Penalty': goals[r.fixture_id].append((int(r.minute),bool(r.is_home)))
    elif r.is_home is not None and r.is_home==r.is_home: X.append((r.fixture_id,int(r.minute),bool(r.is_home),NAME[r.detail]))
X=pd.DataFrame(X,columns=['fixture_id','c','is_home','state']).sort_values(['fixture_id','state','c']).drop_duplicates(['fixture_id','state'])
print("events, first per game",X.state.value_counts().to_dict(),"after minute 85 dropped",int((X.c>85).sum()),flush=True); X=X[X.c<=85].merge(G,on='fixture_id')
EID=list(X.event_id.unique()); px=defaultdict(dict)
for i in range(0,len(EID),1000):
    P=pd.read_sql("SELECT event_id,minute,mkt,sel,ltp::float ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND ((mkt='MO' AND sel IN ('HOME','AWAY')) OR (mkt='OU25' AND sel='OVER')) AND minute BETWEEN 0 AND 95 AND ltp>=1.01 AND ltp<1000",con,params=(EID[i:i+1000],))
    for (e,mk,s),g in P.groupby(['event_id','mkt','sel'],sort=False):
        a=np.full(96,np.nan); a[g.minute.values]=g.ltp.values; px[e][(mk,s)]=a
con.close(); print(f"games with an event {len(EID)}, with prices {len(px)}, {time.time()-T0:.0f}s",flush=True)
rows=[]
for r in X.itertuples():
    b=px.get(r.event_id)
    if not b: continue
    gl=sorted(goals.get(r.fixture_id,[])); sofar=[g for g in gl if g[0]<=r.c]; tot=len(sofar); h=1 if r.season==2024 else 2
    third=gl[2][0] if len(gl)>=3 else None; hw,aw=r.hg>r.ag,r.ag>r.hg
    level=sum(1 for g in sofar if g[1])*2==tot      # is_home is the team credited, no own-goal flip (item 38)
    legs=[('TEAM',b.get(('MO','HOME' if r.is_home else 'AWAY')),hw if r.is_home else aw,None),('OPP',b.get(('MO','AWAY' if r.is_home else 'HOME')),aw if r.is_home else hw,None)]
    if tot<3: legs.append(('OVER',b.get(('OU25','OVER')),r.hg+r.ag>2.5,third))
    for leg,arr,won,gm in legs:
        if arr is None: continue
        for ent,lo,hi in (('E2',2,4),('E5',5,7)):
            for ex,e10 in (('settle',False),('+10',True)):
                for side in 'BL':
                    v=trade(side,arr,r.c,lo,hi,won,e10,gm)
                    if v is None: continue
                    for sp in ('all','<60' if r.c<60 else '60+','level' if level else None):
                        if sp: rows.append((r.state,leg,'BACK' if side=='B' else 'LAY',ent,ex,sp,h,r.event_id,v))
T=pd.DataFrame(rows,columns=['state','leg','side','ent','exit','split','h','g','v']); o=[]
for k,x in T.groupby(['state','leg','side','ent','exit','split']):
    d=line(x.v.values,x.h.values); o.append(dict(zip(['state','leg','side','ent','exit','split'],k))|dict(n=d['n'],games=x.g.nunique(),per10=round(d['per10'],3),t=round(d['t'],2),h1=round(d['h1'],3),h2=round(d['h2'],3),n1=d['n1'],n2=d['n2'],PASS=d['PASS']))
L=pd.DataFrame(o); E=L[L.n>=300].sort_values('t',ascending=False)
print(f"\nlines {len(L)}, at n>=300 {len(E)}, positive {(E.per10>0).sum()}, passing {int(L.PASS.sum())}, {time.time()-T0:.0f}s")
print("\nTOP 15 by t, n>=300"); print(E.head(15).drop(columns=['n1','n2']).to_string(index=False))
print("\nTOP 6 by t, 100<=n<300, for reading only"); print(L[(L.n>=100)&(L.n<300)].sort_values('t',ascending=False).head(6).drop(columns=['n1','n2']).to_string(index=False))
print("\nBOTTOM 5 by t, n>=300"); print(E.tail(5).drop(columns=['n1','n2']).to_string(index=False))
print("\nSURVIVORS"); P=L[L.PASS]
print(P.to_string(index=False) if len(P) else "none")
if len(P):
    print("E2 line with its E5 twin")
    for r in P.itertuples():
        tw=L[(L.state==r.state)&(L.leg==r.leg)&(L.side==r.side)&(L.exit==r.exit)&(L.split==r.split)]; print(tw[['state','leg','side','ent','exit','split','n','per10','t','h1','h2']].to_string(index=False))
print(f"done {time.time()-T0:.0f}s")
PY
