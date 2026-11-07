#!/bin/bash
set -o pipefail
# 499_late_habit (Finder 2026-11-07, queue item 348, Finder's own, source a; engine from jobs/499_late_state.sh): a team's habit of late goals against the Draw and the leader at 70. Rule pushed in the queue before any price. Read only, no tables written. LTP only, so a pass is an upper bound.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(1_800_000_000,1_800_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import defaultdict,Counter,deque
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line
import lib_cand,lib_inplay; lib_cand._checks(); lib_inplay.checks()
from lib_inplay import enter,settle
from lib_official import secs
pd.set_option('display.width',230); pd.set_option('display.max_rows',120); pd.set_option('display.max_columns',30)
T0=time.time()
def counted_goal(t,d): return str(t).lower()=='goal' and d in ('Normal Goal','Penalty','Own Goal')
def score_at(gl,d): return sum(1 for m,h in gl if m<=d and h),sum(1 for m,h in gl if m<=d and not h)
def rolling(games):
    """games: time-ordered (fid,secs,home,away,late goals in the game). fid->LATE, mean of the two teams' late goals per game over their last 10; at least 10; same-time games are not history."""
    H=defaultdict(lambda:deque(maxlen=10)); out={}; i=0
    while i<len(games):
        j=i
        while j<len(games) and games[j][1]==games[i][1]: j+=1
        for f,t,h,a,n in games[i:j]:
            if len(H[h])==10 and len(H[a])==10: out[f]=(sum(H[h])/10+sum(H[a])/10)/2
        for f,t,h,a,n in games[i:j]: H[h].append(n); H[a].append(n)
        i=j
    return out
_g=[(i,i*10,'A','B',1) for i in range(1,11)]+[(11,110,'A','B',5)]; assert rolling(_g)=={11:1.0}
_g=[(i,i*10,'A','B',2 if i>5 else 0) for i in range(1,12)]+[(12,120,'A','B',0)]; _o=rolling(_g); assert _o[11]==1.0 and abs(_o[12]-1.2)<1e-9
assert rolling([(i,10,'A','B',1) for i in range(1,12)])=={}
assert counted_goal('Goal','Own Goal') and not counted_goal('Goal','Missed Penalty') and not counted_goal('Var','Goal cancelled')
assert score_at([(10,True),(60,False),(85,True)],69)==(1,1)
_a=np.full(96,np.nan); _a[71]=5.0
assert enter(_a,70,73,'B')==(71,4.9) and abs(settle('B',4.9,True)-38.22)<1e-9 and enter(_a,70,73,'L')==(71,5.1) and settle('L',5.1,True)==-10
print("checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
F=pd.read_sql("SELECT fixture_id,league_id,season,kickoff,home,away,hg,ag,events_done FROM af_fixtures WHERE status='FT' AND hg IS NOT NULL AND ag IS NOT NULL AND season IN (2023,2024,2025)",con)
EV=pd.read_sql("SELECT fixture_id,coalesce(minute,0) AS mn,is_home,type,detail FROM af_events WHERE fixture_id=ANY(%s) AND (lower(type)='subst' OR type='Goal')",con,params=(list(map(int,F.fixture_id)),))
GO=defaultdict(list); COV=set(); NOSIDE=0
for r in EV.itertuples():
    if str(r.type).lower()=='subst': COV.add(r.fixture_id); continue
    if counted_goal(r.type,r.detail):
        if r.is_home is None or r.is_home!=r.is_home: NOSIDE+=1; continue
        GO[r.fixture_id].append((int(r.mn),bool(r.is_home)))
F['ok']=[(f in COV) and len(GO.get(f,[]))==h+a and sum(1 for m,x in GO.get(f,[]) if x)==h for f,h,a in zip(F.fixture_id,F.hg,F.ag)]
print("fixtures",len(F),"events rebuild FT",int(F.ok.sum()),"goal rows no side",NOSIDE,flush=True)
F['tt']=secs(F.kickoff); R={}
for (l,s),g in F[F.ok].sort_values('tt').groupby(['league_id','season']):
    R.update(rolling([(x.fixture_id,x.tt,x.home,x.away,sum(1 for m,h in GO.get(x.fixture_id,[]) if m>=76)) for x in g.itertuples()]))
ST=pd.DataFrame(list(R.items()),columns=['fixture_id','LATE']).merge(F[['fixture_id','season']],on='fixture_id')
B3=ST[ST.season==2023].LATE; LO,HI=float(B3.quantile(.2)),float(B3.quantile(.8)); print("season 2023 games",len(B3),"LATE cuts",round(LO,3),round(HI,3),"all games mean",round(ST.LATE.mean(),3),flush=True); assert LO<HI and len(B3)>1000
G=pd.read_sql("SELECT m.event_id,f.fixture_id,f.season,f.hg,f.ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL AND f.season IN (2024,2025)",con)
NMS=pd.read_sql("SELECT DISTINCT ON (event_id) event_id,event_name FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt='MO'",con,params=(list(G.event_id),))
BAD=NMS.event_name.str.contains(r"U-?(?:1[5-9]|2[0-3])\b|\(W\)|\bWomen\b| II\b| B(?: v |$)| Reserves?(?: v |$)|^Jong | v Jong ",regex=True); bad=set(NMS.event_id[BAD])
G=G[~G.event_id.isin(bad)].drop_duplicates('fixture_id').drop_duplicates('event_id')
LATE=dict(zip(ST.fixture_id,ST.LATE)); G=G[G.fixture_id.isin(LATE)]; print("games with history and a map",len(G),flush=True)
EID=list(G.event_id); px=defaultdict(dict)
for i in range(0,len(EID),1000):
    P=pd.read_sql("SELECT event_id,minute,sel,ltp::float ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt='MO' AND sel IN ('HOME','AWAY','DRAW') AND minute BETWEEN 70 AND 73 AND ltp>=1.01 AND ltp<1000",con,params=(EID[i:i+1000],))
    for (e,s),g in P.groupby(['event_id','sel'],sort=False):
        a=np.full(96,np.nan); a[g.minute.values]=g.ltp.values; px[e][s]=a
con.close()
rows=[]; SK=Counter()
for r in G.itertuples():
    gl=GO.get(r.fixture_id,[]); b=px.get(r.event_id)
    if not b: SK['no prices 70-73']+=1; continue
    h=1 if r.season==2024 else 2; hw=r.hg>r.ag; aw=r.ag>r.hg; sh,sa=score_at(gl,69); L=LATE[r.fixture_id]
    st='HIGH' if L>=HI else 'LOW' if L<=LO else 'MID'
    if sh==sa: tag,arr,won='DRAW level',b.get('DRAW'),hw==aw
    elif abs(sh-sa)==1:
        ld='HOME' if sh>sa else 'AWAY'; tag,arr,won='LEADER 1',b.get(ld),hw if ld=='HOME' else aw
    else: continue
    if arr is None: SK['no price for state']+=1; continue
    for side in 'BL':
        z=enter(arr,70,73,side)
        if z is None: SK['no print or no bet']+=1; continue
        d,fx=z
        if fx>50: SK['over 50']+=1; continue
        if score_at(gl,d)!=(sh,sa): SK['state changed by entry']+=1; continue
        rows.append((st,tag,'BACK' if side=='B' else 'LAY',h,r.event_id,settle(side,fx,won),won,1/fx))
print("counts",dict(SK),flush=True)
T=pd.DataFrame(rows,columns='st tag side h g v won imp'.split())
assert not T.duplicated(['st','tag','side','g']).any()
o=[]
def rec(nm,x,ctl):
    l=line(x.v.values,x.h.values); o.append(dict(line=nm,n=l['n'],games=x.g.nunique(),per10=round(l['per10'],3),t=round(l['t'],2),h1=round(l['h1'],3),h2=round(l['h2'],3),won=round(x.won.mean(),3),imp=round(x.imp.mean(),3),PASS=l['PASS'] and not ctl))
for (st,tag,side),x in T[T.st!='MID'].groupby(['st','tag','side']): rec(f'{st} {tag} {side}',x,False)
for (tag,side),x in T.groupby(['tag','side']): rec(f'CONTROL all {tag} {side}',x,True)
L=pd.DataFrame(o).sort_values('t',ascending=False)
print(f"\nlines {len(L)}, at n>=300 {(L.n>=300).sum()}, passing {int(L.PASS.sum())}, {time.time()-T0:.0f}s\n"); print(L.to_string(index=False))
print("\n== SURVIVORS"); P=L[L.PASS]; print(P.to_string(index=False) if len(P) else "none")
print(f"done {time.time()-T0:.0f}s")
PY
