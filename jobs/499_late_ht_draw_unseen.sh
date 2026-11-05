#!/bin/bash
set -o pipefail
# 499_late_ht_draw_unseen (Finder 2026-11-05, queue item 134, from jobs/499_goal_timing.sh): back the draw when the favourite leads by one at half-time after a late first-half goal, on Jul-Sep 2026, which did not choose the line. Rule written in the queue before any 2026 price was read. Read only.
# UNSEEN af_fixtures, af_events x bf_hist_other MATCH_ODDS, names matched with lib_cand.loose, market time within 20 min of the af kick-off, as jobs/499_ht_double_change.sh. Only games matched to one market.
# FAVOURITE shorter of home and away at the earliest in-play print within 5 min of market time; a goal with af minute <= 5 drops the game, counted, as that print may follow it.
# CLOCK wall clock only. Restart taken as KO+63 min. Entry first in-play draw print KO+64..67 min, worse of it and the next print within 2 min, one tick adverse. Goal guard as 499_ht_double_change: no trade if a second-half goal has af minute <= 46 + (print - KO - 63 min) + 1, counted. The clock is an estimate, so this guard can also drop a goal just after the print; goals either way are dropped equally.
# BAR about 150-200 trades, so n >= 300 is out of reach. One line scored, EARLY shown as control. No line can pass here.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(3_000_000_000,3_000_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import defaultdict,Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import *
import lib_cand; lib_cand._checks()
pd.set_option('display.width',220); pd.set_option('display.max_columns',30)
T0=time.time()
def entry_wall(ts,px,ko):
    """First print in KO+64..67 min, worse of it and the next within 120 s for a back; (index, price) or None."""
    i=first_idx(ts,ko+64*60,ko+67*60)
    if i is None: return None
    p=float(px[i])
    if i+1<len(ts) and ts[i+1]<=ts[i]+120: p=min(p,float(px[i+1]))
    return i,p
def goal_seen(goal_minutes,t,ko):
    lim=46+(t-ko-63*60)/60+1
    return any(46<=g<=lim for g in goal_minutes)
def timing(goal_minutes,ht_h,ht_a):
    """LATE or EARLY from the last first-half goal, or None if the first-half events do not equal the HT score, or no first-half goal."""
    fh=[g for g in goal_minutes if g<=45]
    if len(fh)!=ht_h+ht_a or not fh: return None
    return 'LATE' if max(fh)>=40 else 'EARLY'
def fav_leads(ht_h,ht_a,ph,pa):
    """True if the shorter-priced side leads by exactly one. Equal prices: False."""
    if ph==pa or abs(ht_h-ht_a)!=1: return False
    return (ht_h>ht_a)==(ph<pa)
assert timing([41],1,0)=='LATE' and timing([39],1,0)=='EARLY' and timing([40],1,0)=='LATE' and timing([45],0,1)=='LATE' and timing([46],1,0) is None and timing([],0,0) is None and timing([10,41,70],2,0)=='LATE'
assert fav_leads(1,0,1.5,6.0) and not fav_leads(1,0,6.0,1.5) and fav_leads(0,1,6.0,1.5) and not fav_leads(2,0,1.5,6.0) and not fav_leads(1,1,1.5,6.0) and not fav_leads(1,0,2.0,2.0)
_t=np.array([3800.,3900.,3950.,4100.]); _p=np.array([3.0,4.0,3.5,9.0])
assert entry_wall(_t,_p,0)==(1,3.5) and entry_wall(np.array([3800.,4100.]),np.array([3.,4.]),0) is None
assert goal_seen([46],3900,0) and goal_seen([49],3900,0) and not goal_seen([50],3900,0) and not goal_seen([30],3900,0)
assert abs(back_settle(step(2.04,-1),True)-(10*(2.02-1)*.98))<1e-9 and back_settle(2.0,False)==-10.0
print("checks: OK",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
F=pd.read_sql("SELECT fixture_id,kickoff,home,away,hg,ag,ht_hg,ht_ag FROM af_fixtures WHERE status='FT' AND hg IS NOT NULL AND ht_hg IS NOT NULL AND kickoff>='2026-07-01' AND kickoff<'2026-10-01' AND league_id NOT IN (2,3)",con)
F['ks']=pd.to_datetime(F.kickoff,utc=True).map(lambda t:t.timestamp()); F['H']=F.home.map(norm); F['A']=F.away.map(norm); F=F.sort_values('ks').reset_index(drop=True); ksv=F.ks.values
E=pd.read_sql("SELECT fixture_id,coalesce(minute,0) mn FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal')",con,params=(list(map(int,F.fixture_id)),))
GL=defaultdict(list)
for a,b in zip(E.fixture_id,E.mn): GL[int(a)].append(int(b))
print(f"af games Jul-Sep 2026 {len(F)}, goal rows {len(E)}",flush=True)
cur.execute("""WITH RECURSIVE t AS ((SELECT market_id FROM bf_hist_other WHERE sport='Soccer' AND market_id>=%s AND market_id<%s ORDER BY market_id LIMIT 1)
 UNION ALL SELECT (SELECT market_id FROM bf_hist_other WHERE sport='Soccer' AND market_id>t.market_id AND market_id<%s ORDER BY market_id LIMIT 1) FROM t WHERE t.market_id IS NOT NULL) SELECT market_id FROM t WHERE market_id IS NOT NULL""",('MATCH_ODDS','MATCH_ODDT','MATCH_ODDT'))
ids=[r[0] for r in cur.fetchall() if '|' in r[0]]; seen=defaultdict(list); print(f"MATCH_ODDS markets on the tape {len(ids)}, {time.time()-T0:.0f}s",flush=True)
for mid in ids:
    _,ev,mt=mid.split('|',2)
    if ' v ' not in ev: continue
    ms=pd.Timestamp(mt).timestamp(); lo,hi=np.searchsorted(ksv,ms-1200),np.searchsorted(ksv,ms+1200,side='right')
    if hi<=lo: continue
    h,_,a=ev.partition(' v '); idx=loose(norm(h),norm(a),[(F.H.iat[i],F.A.iat[i],i) for i in range(lo,hi)])
    if idx is not None: seen[idx].append((mid,h.strip(),a.strip(),ms))
one={k:v[0] for k,v in seen.items() if len(v)==1}; print(f"af games matched to one market {len(one)}; several, dropped {sum(len(v)>1 for v in seen.values())}; {time.time()-T0:.0f}s",flush=True)
SK=Counter(); items=[]
for i,(mid,h,a,ms) in one.items():
    f=F.iloc[i]; g=GL.get(int(f.fixture_id),[])
    if abs(int(f.ht_hg)-int(f.ht_ag))!=1: continue
    tm=timing(g,int(f.ht_hg),int(f.ht_ag))
    if tm is None: SK['first-half events differ from HT score']+=1; continue
    items.append((mid,h,a,ms,tm,int(f.fixture_id),int(f.ht_hg),int(f.ht_ag),f.hg==f.ag,g,f.ks))
mids=[x[0] for x in items]; print(f"one-goal HT games with timing {len(items)}",flush=True); rows=[]; selnames=Counter()
for c in range(0,len(mids),300):
    P=pd.read_sql("SELECT market_id,sel,ts,ltp::float ltp FROM bf_hist_other WHERE sport='Soccer' AND market_id=ANY(%s) AND inplay AND ltp>=1.01 AND ltp<1000",con,params=(mids[c:c+300],))
    P['tt']=(pd.to_datetime(P.ts,utc=True)-pd.Timestamp('1970-01-01',tz='UTC'))/pd.Timedelta(seconds=1); PX={}
    for (m,s),x in P.groupby(['market_id','sel'],sort=False): x=x.sort_values('tt'); PX[(m,s)]=(x.tt.values,x.ltp.values)
    for mid,h,a,ms,tm,fx,hh,ha,drew,g,ks in items[c:c+300]:
        zh,za,zd=PX.get((mid,h)),PX.get((mid,a)),PX.get((mid,'The Draw'))
        if zh is None or za is None or zd is None: SK['runner rows missing']+=1; continue
        ih=first_idx(zh[0],ms,ms+300); ia=first_idx(za[0],ms,ms+300)
        if ih is None or ia is None: SK['no first print']+=1; continue
        if any(x<=5 for x in g): SK['goal by minute 5']+=1; continue
        if not fav_leads(hh,ha,zh[1][ih],za[1][ia]): SK['favourite not leading']+=1; continue
        e=entry_wall(zd[0],zd[1],ms)
        if e is None: SK['no draw print']+=1; continue
        if goal_seen(g,zd[0][e[0]],ms): SK['goal guard']+=1; continue
        a_=step(e[1],-1)
        if a_<=1.01: SK['floor']+=1; continue
        rows.append((tm,fx,ks,e[1],bool(drew),back_settle(a_,bool(drew))))
con.close(); print("counts:",dict(SK),flush=True)
R=pd.DataFrame(rows,columns=['tm','fx','ks','x','won','v']); md=R.ks.median(); R['h']=np.where(R.ks<md,1,2)
print(f"\n== back the draw, favourite one up at HT, Jul-Sep 2026; halves by the median date of all trades here")
for tm,x in R.groupby('tm'):
    l=line(x.v.values,x.h.values); print(f"  {tm}: n {l['n']} games {x.fx.nunique()} per10 {l['per10']:+.3f} t {l['t']:.2f} h1 {l['h1']:+.3f} (n {l['n1']}) h2 {l['h2']:+.3f} (n {l['n2']}) won {x.won.mean():.3f} implied {(1/x.x).mean():.3f} max win {x.v.max():.1f}")
print("\n== SURVIVORS: none can pass at this n; the read is LATE's sign and its gap to EARLY"); print(f"done {time.time()-T0:.0f}s")
PY
