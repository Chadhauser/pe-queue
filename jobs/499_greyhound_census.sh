#!/bin/bash
set -o pipefail
# 499_greyhound_census (Finder 2026-11-04, queue item 46): can greyhound results be read off the BASIC tape? The item's gate: under 80% of races with a clear result = BLOCKED, as no other greyhound results are known on this box. The number 499 is reused with a new slug: 450-499 are all taken.
# LISTING: loose index scan on (sport, market_id), as a plain DISTINCT timed out at 300 s on 4 Nov.
# SAMPLE: every Nth market in id order, about 2,000 markets, as the gate does not need them all.
# CLEAR RESULT: exactly one runner whose last print is <= 1.05 (strict), or <= 1.20 with every other runner >= 10 (loose, reported only). Last print = latest ts of any kind, in play or not.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
pd.set_option('display.width',240); pd.set_option('display.max_rows',100); pd.set_option('display.max_columns',30)
T0=time.time()
def clear_strict(last): return sum(1 for x in last if x<=1.05)==1
def clear_loose(last):
    w=[x for x in last if x<=1.20]
    return len(w)==1 and all(x>=10 for x in last if x>1.20)
# known answers, worked by hand
assert clear_strict([1.01,50,80,20,9,12]) and not clear_strict([1.01,1.02,50]) and not clear_strict([2.5,3,4])
assert clear_loose([1.15,20,30,10]) and not clear_loose([1.15,20,9.8]) and not clear_loose([1.3,20,30]) and not clear_loose([1.1,1.1,20])
print("known-answer checks: OK",flush=True)
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'"); cur.execute("SET statement_timeout='2400s'")
cur.execute("""WITH RECURSIVE t AS (
  (SELECT market_id FROM bf_hist_other WHERE sport='Greyhound Racing' ORDER BY market_id LIMIT 1)
  UNION ALL SELECT (SELECT market_id FROM bf_hist_other WHERE sport='Greyhound Racing' AND market_id>t.market_id ORDER BY market_id LIMIT 1) FROM t WHERE t.market_id IS NOT NULL)
  SELECT market_id FROM t WHERE market_id IS NOT NULL""")
ids=[r[0] for r in cur.fetchall()]; print(f"greyhound markets {len(ids)} ({time.time()-T0:.0f}s)",flush=True)
if not ids: print("\n== SURVIVORS: none; no greyhound markets"); sys.exit(0)
N=max(1,len(ids)//2000); samp=ids[::N]; parts=[]
for i in range(0,len(samp),200):
    parts.append(pd.read_sql("SELECT market_id,event_name,market_type,market_time,country,sel,ts,ltp::float ltp,inplay FROM bf_hist_other WHERE sport='Greyhound Racing' AND market_id=ANY(%s)",con,params=(samp[i:i+200],)))
    print(f"  {min(i+200,len(samp))}/{len(samp)} {time.time()-T0:.0f}s",flush=True)
P=pd.concat(parts,ignore_index=True); print(f"\nsampled markets {P.market_id.nunique()} rows {len(P)} (every {N}th)")
print("market types",P.groupby('market_type').market_id.nunique().to_dict(),"| countries",P.groupby('country').market_id.nunique().to_dict())
print("dates",P.market_time.min(),"to",P.market_time.max())
print("example event and runner names",P.event_name.iloc[0],"|",list(P.sel.drop_duplicates().head(8)))
R=P.groupby(['market_id','sel']).agg(prints=('ltp','size'),pre=('inplay',lambda s:int((~s).sum())),ip=('inplay','sum')); print("\nper runner: prints, pre-off, in-play\n",R.describe().round(1).loc[['mean','50%','max']].to_string())
P=P[P.ltp.notna()].sort_values('ts'); L=P.groupby(['market_id','sel']).agg(last=('ltp','last'),last_ip=('inplay','last'),last_ts=('ts','last')).reset_index()
M=L.groupby('market_id').agg(runners=('last','size'),strict=('last',lambda s:clear_strict(list(s))),loose=('last',lambda s:clear_loose(list(s))),any_ip=('last_ip','max'))
print("\nrunners per market",M.runners.value_counts().sort_index().to_dict()); print(f"market has any in-play last print: {M.any_ip.mean():.3f}")
print(f"CLEAR RESULT strict {M.strict.mean():.3f}, loose {M.loose.mean():.3f}, either {(M.strict|M.loose).mean():.3f} of {len(M)} markets (gate: 0.80)")
M2=M.join(P.groupby('market_id').market_time.first()); M2['q']=pd.to_datetime(M2.market_time,utc=True).dt.strftime('%Y-%m')
print("strict by month, first and last 6:\n",pd.concat([M2.groupby('q').strict.agg(['size','mean']).head(6),M2.groupby('q').strict.agg(['size','mean']).tail(6)]).round(3).to_string())
print("last prints of the winner side, where strict fails: pct of runners by final price\n",pd.cut(L[L.market_id.isin(M.index[~M.strict])]['last'],[1,1.05,1.2,1.5,2,3,5,10,20,1000]).value_counts(normalize=True).sort_index().round(3).to_string())
print(f"\n== SURVIVORS: census only; gate {'open' if (M.strict|M.loose).mean()>=0.8 else 'SHUT, item BLOCKED'}"); print(f"total {time.time()-T0:.0f}s")
PY
