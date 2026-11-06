#!/bin/bash
set -o pipefail
# 499_fh3_aug24 (Finder 2026-11-06, queue item 212, interim on item 139): back FH25 Over at about 15 min at 0-0, Aug 2024, Sep 2024 as the control. Rule pushed before these prices were read. goal_timeline does not reach 2024, so scores come from af_events and af_fixtures through af_price_map: mapped games only, and the clock stands in for the feed minute.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))  # this job only
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line,first_idx
from lib_official import bk,fill,secs
import lib_cand; lib_cand._checks()
T0=time.time()
def clean_at(t,off,goals):
    """No goal with af minute at or before the print's clock minute + 2. goals: af minutes."""
    return not any(g<=(t-off)/60+2 for g in goals)
# known answers, worked by hand
assert clean_at(1000.,100.,[]) and clean_at(1000.,100.,[18]) and not clean_at(1000.,100.,[17]) and not clean_at(1000.,100.,[5])      # print at clock minute 15, +2 = 17
_T=np.array([800.,950.,1000.]); assert first_idx(_T,900.,1199.)==1 and first_idx(_T,1100.,1199.) is None
# Back 41 -> 40 (one tick), win 390 less 2% = 382.2; lose -10.
assert abs(bk(41.0,True)-382.2)<1e-9 and bk(41.0,False)==-10.0
print("checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
cur.execute("""SELECT DISTINCT o.market_id,o.event_id,o.market_time,f.fixture_id,f.ht_hg,f.ht_ag FROM bf_hist_other o JOIN af_price_map m ON m.event_id::text=o.event_id
               JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE o.sport='Soccer' AND o.market_type='FIRST_HALF_GOALS_25' AND o.market_time>='2024-08-01' AND o.market_time<'2024-10-01' AND f.ht_hg IS NOT NULL""")
M=pd.DataFrame(cur.fetchall(),columns='mid e mt fx hh ha'.split()); print(f"mapped FH25 markets {len(M)}, {time.time()-T0:.0f}s",flush=True)
if M.empty: print("no mapped markets; cannot score\n== SURVIVORS: none"); sys.exit(0)
M['off']=secs(M.mt); M=M.sort_values('mid').drop_duplicates('e')
EV=pd.read_sql("SELECT fixture_id,coalesce(minute,0) mn FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal')",con,params=(list(map(int,M.fx)),))
GL={k:list(v.mn) for k,v in EV.groupby('fixture_id')}
P=pd.read_sql("SELECT market_id,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_id=ANY(%s) AND inplay AND ltp>=1.01 AND ltp<1000",con,params=(list(M.mid),)); con.close()
P=P[P.sel.str.strip().str.lower().str.startswith('over')].copy(); P['tt']=secs(P.ts); P=P.drop_duplicates(['market_id','tt']).sort_values('tt',kind='stable'); PX={k:g for k,g in P.groupby('market_id')}
SK=Counter(); rows=[]
for r in M.itertuples():
    x=PX.get(r.mid)
    if x is None: SK['no in-play Over print']+=1; continue
    ts,px=x.tt.values,x.ltp.values; i=first_idx(ts,r.off+900,r.off+1199)
    if i is None: SK['no print in the window']+=1; continue
    if not clean_at(ts[i],r.off,GL.get(r.fx,[])): SK['not 0-0 at the print']+=1; continue
    p=fill(ts,px,i,'B'); won=(r.hh+r.ha)>2.5; v=bk(p,won)
    if v is None: SK['bottom of ladder']+=1; continue
    rows.append((pd.Timestamp(r.mt).tz_convert('UTC').strftime('%Y-%m'),r.e,r.off,p,won,v))
print("counted:",dict(sorted(SK.items())),flush=True)
R=pd.DataFrame(rows,columns='mo e off p won v'.split()); out=[]
for mo,x in R.groupby('mo'):
    md=np.median(x.off.values); l=line(x.v.values,np.where(x.off<md,1,2)); out.append(dict(month=mo,scored='SCORED' if mo=='2024-08' else 'control',n=l['n'],per10=l['per10'],t=l['t'],h1=l['h1'],h2=l['h2'],won=x.won.mean(),imp=(1/x.p).mean(),maxwin=l['maxwin'],PASS=l['PASS'] and mo=='2024-08'))
O=pd.DataFrame(out); print(O.round(3).to_string(index=False)); S=O[O.PASS]; print(f"\n== SURVIVORS: {len(S)}"); print(S.round(3).to_string(index=False) if len(S) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
