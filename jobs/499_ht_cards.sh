#!/bin/bash
set -o pipefail
# 499_ht_cards (Finder 2026-11-05, queue item 181, Finder's own, source d): yellow cards at half-time as a state. Rule pushed to the queue before any price was read.
# STATE yellows with af minute <= 45 (45+n included). First-half red out. No substitution row at all = not covered, out. Y01 0-1, Y23 2-3, Y4 4+. HT goals G0, G1, G2 for Over 2.5; G0, G1 for Over 1.5. MO at a level HT score: the side with at least 2 more yellows HEAVY, the other LIGHT.
# ENTRY first print tape 47..52, as tape 46 is still the first half (jobs/499_goal_timing.sh); worse of it and the next within 2, one tick adverse; no trade if a second-half goal has come by that minute. No print: no trade, never a forward fill. Held to the result, 2% commission, £10 risk, one bet per game per line. Halves by season.
# A bucket is read against the same goal state with Y01 (t_v_Y01), since the market's general error at that state is not a card effect.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import defaultdict,Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line
import lib_cand,lib_inplay; lib_cand._checks(); lib_inplay.checks()
from lib_inplay import *
pd.set_option('display.width',250); pd.set_option('display.max_rows',300); pd.set_option('display.max_columns',40)
T0=time.time()
def yb(n): return 'Y01' if n<=1 else 'Y23' if n<=3 else 'Y4'
def first_half(minute): return minute<=45
def heavy(yh,ya):
    """Side with at least 2 more first-half yellows, else None."""
    return 'HOME' if yh-ya>=2 else 'AWAY' if ya-yh>=2 else None
def second_half_goal_by(goals,d):
    """Any goal with af minute after 45 and at or before tape minute d."""
    return any(45<m<=d for m in goals)
assert yb(0)=='Y01' and yb(1)=='Y01' and yb(2)=='Y23' and yb(3)=='Y23' and yb(4)=='Y4' and yb(9)=='Y4'
assert first_half(45) and not first_half(46)
assert heavy(3,1)=='HOME' and heavy(1,3)=='AWAY' and heavy(2,1) is None and heavy(0,0) is None
assert second_half_goal_by([30,47],47) and not second_half_goal_by([30,48],47) and not second_half_goal_by([45],50) and second_half_goal_by([46],47)
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
G=pd.read_sql("""SELECT m.event_id,f.fixture_id,f.season,f.hg,f.ag,f.ht_hg,f.ht_ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL AND f.ht_hg IS NOT NULL AND f.season IN (2024,2025)""",con)
ids=list(map(int,G.fixture_id))
EV=pd.read_sql("SELECT fixture_id,coalesce(minute,0) AS minute,is_home,type,detail FROM af_events WHERE fixture_id=ANY(%s) AND (type IN ('Card','subst','Subst') OR (type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal')))",con,params=(ids,))
print("event types",EV.type.value_counts().to_dict(),flush=True)
YL=defaultdict(lambda:[0,0]); RED=set(); COV=set(); GO=defaultdict(list)
for r in EV.itertuples():
    t=str(r.type).lower()
    if t=='subst': COV.add(r.fixture_id)
    elif t=='goal': GO[r.fixture_id].append(int(r.minute))
    elif first_half(r.minute):
        if r.detail in ('Red Card','Second Yellow Card'): RED.add(r.fixture_id)
        elif r.detail=='Yellow Card' and r.is_home==r.is_home and r.is_home is not None: YL[r.fixture_id][0 if r.is_home else 1]+=1
EID=list(G.event_id.unique()); px=defaultdict(dict)
for i in range(0,len(EID),1000):
    P=pd.read_sql("SELECT event_id,minute,mkt,sel,ltp::float ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND ((mkt='MO' AND sel IN ('HOME','AWAY')) OR (mkt IN ('OU25','OU15') AND sel='OVER')) AND minute BETWEEN 47 AND 56 AND ltp>=1.01 AND ltp<1000",con,params=(EID[i:i+1000],))
    for (e,mk,s),g in P.groupby(['event_id','mkt','sel'],sort=False):
        a=np.full(96,np.nan); a[g.minute.values]=g.ltp.values; px[e][(mk,s)]=a
    print(f"  prices {min(i+1000,len(EID))}/{len(EID)} | {time.time()-T0:.0f}s",flush=True)
con.close()
rows=[]; SK=Counter(); DIST=Counter()
for r in G.itertuples():
    if r.fixture_id not in COV: SK['no substitution row, not covered']+=1; continue
    if r.fixture_id in RED: SK['first-half red']+=1; continue
    b=px.get(r.event_id)
    if not b: SK['no prices 47-56']+=1; continue
    yh,ya=YL[r.fixture_id]; Y=yb(yh+ya); hg=r.ht_hg+r.ht_ag; h=1 if r.season==2024 else 2; DIST[Y]+=1; tot=r.hg+r.ag; gl=GO.get(r.fixture_id,[])
    legs=[]
    if hg<=2: legs.append((f'OU25',f'G{hg}',Y,b.get(('OU25','OVER')),tot>2.5))
    if hg<=1: legs.append((f'OU15',f'G{hg}',Y,b.get(('OU15','OVER')),tot>1.5))
    hv=heavy(yh,ya)
    if hv and r.ht_hg==r.ht_ag:
        lt='AWAY' if hv=='HOME' else 'HOME'; wn={'HOME':r.hg>r.ag,'AWAY':r.ag>r.hg}
        legs.append(('MO','LEVEL','HEAVY',b.get(('MO',hv)),wn[hv])); legs.append(('MO','LEVEL','LIGHT',b.get(('MO',lt)),wn[lt]))
    for mk,st,bk,arr,won in legs:
        if arr is None: SK[f'{mk} no prices']+=1; continue
        for side in 'BL':
            e=enter(arr,47,52,side)
            if e is None: SK[f'{mk} no print or no bet']+=1; continue
            d,fx=e
            if second_half_goal_by(gl,d): SK['second-half goal by entry']+=1; continue
            rows.append((mk,st,bk,'BACK' if side=='B' else 'LAY',h,r.event_id,settle(side,fx,won),won,1/fx))
print("counts",dict(SK),"games by bucket",dict(DIST),flush=True)
T=pd.DataFrame(rows,columns='mkt st bk side h g v won imp'.split()); o=[]
B={k:x.v.values for k,x in T[T.bk=='Y01'].groupby(['mkt','st','side'])}
for k,x in T.groupby(['mkt','st','bk','side']):
    d=line(x.v.values,x.h.values); nv=B.get((k[0],k[1],k[3])); dt=np.nan
    if k[2] in ('Y23','Y4') and nv is not None and len(nv)>1 and len(x)>1: dt=(x.v.mean()-nv.mean())/np.sqrt(x.v.var(ddof=1)/len(x)+nv.var(ddof=1)/len(nv))
    o.append(dict(zip(['mkt','st','bk','side'],k))|dict(n=d['n'],games=x.g.nunique(),per10=round(d['per10'],3),t=round(d['t'],2),h1=round(d['h1'],3),h2=round(d['h2'],3),n1=d['n1'],n2=d['n2'],won=round(x.won.mean(),3),implied=round(x.imp.mean(),3),t_v_Y01=round(dt,2) if dt==dt else np.nan,PASS=d['PASS']))
L=pd.DataFrame(o).sort_values('t',ascending=False)
print(f"\nlines {len(L)}, at n>=300 {(L.n>=300).sum()}, passing {int(L.PASS.sum())}, {time.time()-T0:.0f}s\n"); print(L.drop(columns=['n1','n2']).to_string(index=False))
print("\n== SURVIVORS"); P=L[L.PASS]; print(P.drop(columns=['n1','n2']).to_string(index=False) if len(P) else "none")
print(f"done {time.time()-T0:.0f}s")
PY
