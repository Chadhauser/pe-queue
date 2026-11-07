#!/bin/bash
set -o pipefail
# 499_late_state (Finder 2026-11-07, queue items 333 and 334, Finder's own): is a stop-start second half priced at 85, and the booked side at 70. Rules pushed in the queue before any price. Read only, no tables written. LTP only, so a pass is an upper bound.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(1_800_000_000,1_800_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import defaultdict,Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line
import lib_cand,lib_inplay; lib_cand._checks(); lib_inplay.checks()
from lib_inplay import enter,settle
pd.set_option('display.width',230); pd.set_option('display.max_rows',120); pd.set_option('display.max_columns',30)
T0=time.time()
def stop_bucket(n): return 'LOW' if n<=2 else 'MID' if n<=5 else 'HIGH'
def is_stop(t,d,mn):
    """Second-half stoppage row at af minute 46-84: goal, missed penalty, card or Var. A substitution is not one."""
    return 46<=mn<=84 and t.lower() in ('goal','card','var')
def counted_goal(t,d): return t.lower()=='goal' and d in ('Normal Goal','Penalty','Own Goal')
def score_at(gl,d):
    """gl is (minute,is_home). Home and away goals at af minute <= d."""
    return sum(1 for m,h in gl if m<=d and h),sum(1 for m,h in gl if m<=d and not h)
def heavy(yh,ya): return 'HOME' if yh-ya>=2 else 'AWAY' if ya-yh>=2 else None
assert [stop_bucket(x) for x in (0,2,3,5,6,14)]==['LOW','LOW','MID','MID','HIGH','HIGH']
assert is_stop('Goal','Missed Penalty',46) and is_stop('Card','Yellow Card',84) and is_stop('Var','Goal cancelled',60)
assert not is_stop('subst','Substitution 1',60) and not is_stop('Card','Yellow Card',45) and not is_stop('Card','Yellow Card',85)
assert counted_goal('Goal','Own Goal') and not counted_goal('Goal','Missed Penalty') and not counted_goal('Var','Goal cancelled')
assert score_at([(10,True),(60,False),(85,True)],84)==(1,1) and score_at([(10,True),(60,False),(85,True)],85)==(2,1)
assert heavy(3,1)=='HOME' and heavy(0,2)=='AWAY' and heavy(2,1) is None
# hand-worked: entry at a one-tick-adverse fill 5.0->4.9 backed, wins 10*3.9*0.98=38.22; lay 5.0->5.1 stake 10/4.1, keeps 2.3902 after 2%
_a=np.full(96,np.nan); _a[85]=5.0
assert enter(_a,85,88,'B')==(85,4.9) and abs(settle('B',4.9,True)-38.22)<1e-9 and enter(_a,85,88,'L')==(85,5.1) and abs(settle('L',5.1,False)-10/4.1*.98)<1e-9 and settle('L',5.1,True)==-10
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
G=pd.read_sql("SELECT m.event_id,f.fixture_id,f.season,f.hg,f.ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL AND f.season IN (2024,2025)",con)
NMS=pd.read_sql("SELECT DISTINCT ON (event_id) event_id,event_name FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt='MO'",con,params=(list(G.event_id),))
BAD=NMS.event_name.str.contains(r"U-?(?:1[5-9]|2[0-3])\b|\(W\)|\bWomen\b| II\b| B(?: v |$)| Reserves?(?: v |$)|^Jong | v Jong ",regex=True); bad=set(NMS.event_id[BAD])
print("maps naming a youth, women or reserve game, dropped",len(bad),"of",len(G),flush=True); G=G[~G.event_id.isin(bad)].drop_duplicates('fixture_id').drop_duplicates('event_id')
ids=list(map(int,G.fixture_id))
EV=pd.read_sql("SELECT fixture_id,coalesce(minute,0) AS mn,is_home,type,detail FROM af_events WHERE fixture_id=ANY(%s)",con,params=(ids,))
STOP=Counter(); COV=set(); GO=defaultdict(list); YL=defaultdict(lambda:[0,0]); RED=set(); NOSIDE=0
for r in EV.itertuples():
    t=str(r.type); d=r.detail; home=r.is_home
    if t.lower()=='subst': COV.add(r.fixture_id); continue
    if is_stop(t,d,r.mn): STOP[r.fixture_id]+=1
    if counted_goal(t,d):
        if home is None or home!=home: NOSIDE+=1; continue
        # af_events is_home names the team credited; an own goal row in this feed is checked against FT below
        GO[r.fixture_id].append((int(r.mn),bool(home)))
    if t.lower()=='card' and r.mn<=69:
        if d in ('Red Card','Second Yellow Card'): RED.add(r.fixture_id)
        elif d=='Yellow Card' and home is not None and home==home: YL[r.fixture_id][0 if home else 1]+=1
EID=list(G.event_id); px=defaultdict(dict)
for i in range(0,len(EID),1000):
    P=pd.read_sql("SELECT event_id,minute,mkt,sel,ltp::float ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND ((mkt='MO' AND sel IN ('HOME','AWAY','DRAW')) OR (mkt IN ('OU15','OU25','OU35') AND sel='OVER')) AND minute BETWEEN 70 AND 90 AND ltp>=1.01 AND ltp<1000",con,params=(EID[i:i+1000],))
    for (e,mk,s),g in P.groupby(['event_id','mkt','sel'],sort=False):
        a=np.full(96,np.nan); a[g.minute.values]=g.ltp.values; px[e][(mk,s)]=a
    print(f"  prices {min(i+1000,len(EID))}/{len(EID)} | {time.time()-T0:.0f}s",flush=True)
con.close()
rows=[]; SK=Counter(); DIST=Counter(); mism=0
OVR={1:'OU15',2:'OU25',3:'OU35'}
def add(item,st,tag,side_lab,arr,lo,hi,won,h,e,gl,chk,cap=50.0):
    if arr is None: SK[f'{item} {tag} no prices']+=1; return
    for side in 'BL':
        z=enter(arr,lo,hi,side)
        if z is None: SK[f'{item} no print or no bet']+=1; continue
        d,fx=z
        if fx>cap: SK[f'{item} over {cap:.0f}']+=1; continue
        if not chk(d): SK[f'{item} state changed by entry']+=1; continue
        rows.append((item,st,tag,'BACK' if side=='B' else 'LAY',h,e,settle(side,fx,won),won,1/fx))
for r in G.itertuples():
    if r.fixture_id not in COV: SK['no substitution row, not covered']+=1; continue
    gl=GO.get(r.fixture_id,[])
    if len(gl)!=r.hg+r.ag or sum(1 for m,x in gl if x)!=r.hg:
        mism+=1; SK['goal rows do not rebuild FT, dropped from both (counted)']+=1; continue
    b=px.get(r.event_id)
    if not b: SK['no prices 70-90']+=1; continue
    h=1 if r.season==2024 else 2; tot=r.hg+r.ag; hw=r.hg>r.ag; aw=r.ag>r.hg
    # item 333
    S=stop_bucket(STOP[r.fixture_id]); DIST[S]+=1
    sh,sa=score_at(gl,84)
    def same(d,sh=sh,sa=sa,gl=gl): return score_at(gl,d)==(sh,sa)
    g=sh+sa
    if g in OVR:
        arr=b.get((OVR[g],'OVER')); wn=tot>g+0.5
        add('333',S,'NEXT all','OVER',arr,85,88,wn,h,r.event_id,gl,same)
        add('333',S,f'NEXT G{g}','OVER',arr,85,88,wn,h,r.event_id,gl,same)
    if sh==sa: add('333',S,'DRAW level','DRAW',b.get(('MO','DRAW')),85,88,hw==aw,h,r.event_id,gl,same)
    if abs(sh-sa)==1:
        ld='HOME' if sh>sa else 'AWAY'
        add('333',S,'LEADER 1','LEAD',b.get(('MO',ld)),85,88,hw if ld=='HOME' else aw,h,r.event_id,gl,same)
    # item 334
    if r.fixture_id in RED: SK['334 red by 69']+=1; continue
    yh,ya=YL[r.fixture_id]; hv=heavy(yh,ya); sh,sa=score_at(gl,69)
    def same2(d,sh=sh,sa=sa,gl=gl): return score_at(gl,d)==(sh,sa)
    if sh==sa:
        if hv:
            lt='AWAY' if hv=='HOME' else 'HOME'
            add('334','LEVEL','HEAVY',hv,b.get(('MO',hv)),70,73,hw if hv=='HOME' else aw,h,r.event_id,gl,same2)
            add('334','LEVEL','LIGHT',lt,b.get(('MO',lt)),70,73,hw if lt=='HOME' else aw,h,r.event_id,gl,same2)
        else:
            add('334','LEVEL','CONTROL NONE','HOME',b.get(('MO','HOME')),70,73,hw,h,r.event_id,gl,same2)
            add('334','LEVEL','CONTROL NONE','AWAY',b.get(('MO','AWAY')),70,73,aw,h,r.event_id,gl,same2)
    elif abs(sh-sa)==1:
        ld='HOME' if sh>sa else 'AWAY'; arr=b.get(('MO',ld)); wn=hw if ld=='HOME' else aw
        tag='CONTROL NONE' if hv is None else 'LEADER_HEAVY' if hv==ld else 'LEADER_LIGHT'
        add('334','LEAD1',tag,ld,arr,70,73,wn,h,r.event_id,gl,same2)
print("counts",dict(SK),"\ngoal rows missing a side",NOSIDE,"games by stop bucket",dict(DIST),flush=True)
T=pd.DataFrame(rows,columns='item st tag side h g v won imp'.split())
d=T.duplicated(['item','st','tag','side','g'])&~T.tag.str.contains('CONTROL'); print("duplicate bets per game per scored line (the level-score control holds both sides by design)",int(d.sum()),flush=True); assert not d.any()
o=[]
LOW={k:x.v.values for k,x in T[(T.item=='333')&(T.st=='LOW')].groupby(['tag','side'])}
for k,x in T.groupby(['item','st','tag','side']):
    l=line(x.v.values,x.h.values); dt=np.nan; nv=LOW.get((k[2],k[3])) if k[0]=='333' else None
    if nv is not None and k[1]!='LOW' and len(x)>1 and len(nv)>1: dt=(x.v.mean()-nv.mean())/np.sqrt(x.v.var(ddof=1)/len(x)+nv.var(ddof=1)/len(nv))
    o.append(dict(item=k[0],st=k[1],tag=k[2],side=k[3],n=l['n'],games=x.g.nunique(),per10=round(l['per10'],3),t=round(l['t'],2),h1=round(l['h1'],3),h2=round(l['h2'],3),n1=l['n1'],n2=l['n2'],won=round(x.won.mean(),3),imp=round(x.imp.mean(),3),t_v_LOW=round(dt,2) if dt==dt else np.nan,PASS=l['PASS'] and 'CONTROL' not in k[2]))
L=pd.DataFrame(o).sort_values('t',ascending=False)
print(f"\nlines {len(L)}, at n>=300 {(L.n>=300).sum()}, passing {int(L.PASS.sum())}, {time.time()-T0:.0f}s\n"); print(L.drop(columns=['n1','n2']).to_string(index=False))
print("\n== SURVIVORS"); P=L[L.PASS]; print(P.drop(columns=['n1','n2']).to_string(index=False) if len(P) else "none")
print(f"done {time.time()-T0:.0f}s")
PY
