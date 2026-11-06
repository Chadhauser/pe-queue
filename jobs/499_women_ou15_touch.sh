#!/bin/bash
set -o pipefail
# 499_women_ou15_touch (Finder 2026-11-06, queue item 270, Finder's own, source a; from jobs/499_dnb_touch.sh): can item 269's line be taken? The real touch on OU1.5 Under before the off, women v senior, liq_sample local copy. A pilot on days only: no result is read, it cannot pass. Read only.
# Last pre-off row per game, minute 0 and at least 2 min before the game's first in-play row, so a row at the off itself is not read as a pre-off touch. spread = implied at back minus implied at lay, in points. cost v print = how far the back touch sits below the last print, in points of implied.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_official import group,secs,checks
checks()
def pts(a,b): return 100*(1/a-1/b)
assert abs(pts(4,5)-5)<1e-9 and abs(pts(2,2))<1e-9   # .25-.20 is 5 points
print("checks: OK",flush=True)
pd.set_option('display.width',200); pd.set_option('display.max_columns',30)
con=psycopg2.connect(creds.pg_local()); con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='600s'")
print("markets named like OU15:",pd.read_sql("SELECT mkt,count(*) n FROM liq_sample WHERE mkt ILIKE '%15%' GROUP BY 1",con).to_dict('records'),flush=True)
P=pd.read_sql("SELECT DISTINCT ts,event_name ev,sel,back_px::float8 b,lay_px::float8 l,back_sz::float8 bs,ltp::float8 ltp FROM liq_sample WHERE mkt='OU15' AND minute=0 AND lower(sel) LIKE 'under%' AND back_px>=1.01 AND lay_px>back_px AND lay_px<1000",con)
F=pd.read_sql("SELECT event_name ev,min(ts) t1 FROM liq_sample WHERE mkt='OU15' AND minute>=1 GROUP BY 1",con); con.close()
P['tt']=secs(P.ts); F['t1']=secs(F.t1); print("rows",len(P),"games",P.ev.nunique(),"range",P.ts.min(),P.ts.max(),flush=True)
P=P.merge(F,on='ev',how='left'); seen=P.t1.notna(); print("games with no in-play row, kept out, off time unknown:",P[~seen].ev.nunique(),flush=True)
P=P[seen&(P.tt<=P.t1-120)].sort_values('tt',kind='stable').drop_duplicates('ev',keep='last')
P['g']=P.ev.map(lambda e:group(e) or 'SENIOR'); P['sp']=pts(P.b,P.l); P['cost']=np.where(P.ltp.notna(),pts(P.b,P.ltp),np.nan); P['mins']=(P.t1-P.tt)/60
out=[]
for g,x in P.groupby('g'):
    out.append(dict(g=g,games=len(x),mins_before_p50=x.mins.median(),back_p50=x.b.median(),lay_p50=x.l.median(),spread_p25=x.sp.quantile(.25),spread_p50=x.sp.median(),spread_p75=x.sp.quantile(.75),cost_v_print_p50=x.cost.median(),back_size_p50=x.bs.median(),share_spread_under_2=(x.sp<2).mean(),imp_back=(1/x.b).mean()))
print(pd.DataFrame(out).round(3).to_string(index=False))
print("\n== SURVIVORS: a pilot, cannot pass, none");
PY
