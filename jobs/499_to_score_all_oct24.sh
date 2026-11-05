#!/bin/bash
set -o pipefail
# 499_to_score_all_oct24 (Finder 2026-11-05, queue item 165, Finder's own, source c; from jobs/499_away_scorer_may.sh): lay every player to score, both sides, on Oct 2024, official results. Rule pushed in the queue before any Oct 2024 TO_SCORE price was read. Read only.
# RULE first non-in-play print T-30 min to the off, all runners, prices to 200, lay at the worse of it and the next within 120 s, one tick adverse, 2%, £10 liability, hold to WINNER or LOSER, any other status void, counted. Many runners a game: tg, t on per-game sums, is the figure to read. Thin prints: a pass is an upper bound and earns only a player_liq touch check.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import tstat,line,step,lay_settle
from lib_official import ly,secs,first_in,fill,checks
import lib_cand; lib_cand._checks(); checks()
pd.set_option('display.width',230)
# known answers: lay 6.0 -> 6.2: stake 10/5.2 = 1.923, wins 1.8846, loses -10. first_in over T-30 to the off never reaches back before T-30.
assert abs(ly(6.0,False)-1.884615)<1e-5 and ly(6.0,True)==-10.0
_t=np.array([100.,800.,860.]); _p=np.array([9.,6.,6.4]); _i=first_in(_t,200.,2000.); assert _i==1 and fill(_t,_p,_i,'L')==6.4
print("checks: OK",flush=True); T0=time.time()
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
P=pd.read_sql("SELECT market_id,event_id,event_name ev,market_time mt,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type='TO_SCORE' AND market_time>='2024-10-01' AND market_time<'2024-11-01' AND NOT inplay AND ltp>=1.01 AND ltp<1000 AND ts>=market_time-interval '30 minutes'",con)
RS=pd.read_sql("SELECT market_id,sel,status FROM bf_hist_result WHERE sport='Soccer' AND market_type='TO_SCORE' AND market_id=ANY(%s)",con,params=(list(P.market_id.unique()),)); con.close()
print(f"prints {len(P):,}, markets {P.market_id.nunique()}, events {P.event_id.nunique()}; result rows {len(RS)}, markets with results {RS.market_id.nunique()}; statuses {RS.status.value_counts().to_dict()}",flush=True)
ST={(a,b):c for a,b,c in zip(RS.market_id,RS.sel,RS.status)}; P['tt']=secs(P.ts); P['off']=secs(P.mt); P=P.drop_duplicates(['market_id','sel','tt']).sort_values('tt',kind='stable')
C=Counter(); rows=[]
for (m,s),y in P.groupby(['market_id','sel'],sort=False):
    st=ST.get((m,s))
    if st is None: C['no result row']+=1; continue
    if st not in ('WINNER','LOSER'): C['void: '+str(st)]+=1; continue
    ts,px=y.tt.values,y.ltp.values; o=float(y.off.iloc[0]); i=first_in(ts,o-1800,o)
    if i is None: C['no print in window']+=1; continue
    p=fill(ts,px,i,'L')
    if p>200: C['over 200']+=1; continue
    won=st=='WINNER'; rows.append((y.event_id.iloc[0],o,s,p,won,ly(p,won)))
print("counted:",dict(sorted(C.items())),flush=True)
R=pd.DataFrame(rows,columns='e off sel p won v'.split())
if R.empty: print("\n== SURVIVORS: none (no trades)"); sys.exit(0)
md=R.groupby('e').off.first().median(); l=line(R.v.values,np.where(R.off<=md,1,2)); tg=tstat(R.groupby('e').v.sum().values)
print(f"\nALL lay, THE SCORED LINE n {l['n']} games {R.e.nunique()} per10 {l['per10']:+.3f} t {l['t']:.2f} tg {tg:.2f} h1 {l['h1']:+.3f} (n {l['n1']}) h2 {l['h2']:+.3f} (n {l['n2']}) won {R.won.mean():.3f} implied {(1/R.p.map(lambda q:step(q,1))).mean():.3f} maxwin {l['maxwin']:.2f}")
for lo,hi in ((1,4),(4,6),(6,10),(10,20),(20,200.01)):
    x=R[(R.p>=lo)&(R.p<hi)]
    if len(x): print(f"  context p {lo}-{hi:.0f}: n {len(x)} per10 {x.v.mean():+.3f} t {tstat(x.v.values):.2f} won {x.won.mean():.3f}")
print("\n== SURVIVORS (standard bar and tg >= 3.5)"); print("ALL lay PASS" if l['PASS'] and tg>=3.5 else "none"); print(f"done {time.time()-T0:.0f}s")
PY
