#!/bin/bash
set -o pipefail
# 499_dup_ids_census (Finder 2026-11-05, queue item 151; check, not a price test): which markets on bf_hist_other are held under two ids for one event, by sport, type and month. Read only.
# A pair counts only if both ids share the event and the market time, as one event can truly hold two markets of a type. Prints compared on one sample per month: the share of real-id prints with the same selection, time and price under the other id.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd
sys.path.insert(0,'/root/pe-queue/runner'); import creds
def form(m): return 'name' if '|' in str(m) else 'real'
assert form('1.234')=='real' and form('MATCH_ODDS|123|2026-09-01T12:00')=='name'
print("checks: OK",flush=True); T0=time.time()
pd.set_option('display.width',200); pd.set_option('display.max_rows',500)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
out=[]
for sport,types in (('Soccer',('MATCH_ODDS','OVER_UNDER_25','OVER_UNDER_15','OVER_UNDER_35','BOTH_TEAMS_TO_SCORE','FIRST_HALF_GOALS_05')),('Tennis',('MATCH_ODDS',)),('Cricket',('MATCH_ODDS',))):
    M=pd.read_sql("SELECT market_type,market_id,event_id,market_time FROM bf_hist_other WHERE sport=%s AND market_type=ANY(%s) GROUP BY 1,2,3,4",con,params=(sport,list(types)))
    print(f"{sport}: markets {len(M)}, {time.time()-T0:.0f}s",flush=True)
    M['form']=M.market_id.map(form); M['mon']=pd.to_datetime(M.market_time,utc=True).dt.strftime('%Y-%m')
    for (ty,mon),g in M.groupby(['market_type','mon']):
        k=g.groupby(['event_id','market_time']); sz=k.size(); both=k.form.nunique()
        out.append(dict(sport=sport,type=ty,mon=mon,markets=len(g),events=g.event_id.nunique(),real=int((g.form=='real').sum()),name=int((g.form=='name').sum()),twice=int((sz>1).sum()),both_forms=int((both>1).sum())))
    D=M[M.market_type=='MATCH_ODDS']; pairs=D.groupby(['event_id','market_time']).filter(lambda x:x.form.nunique()>1)
    for mon,g in pairs.groupby('mon'):
        e=g.event_id.iloc[0]; ids=g[g.event_id==e]; r=ids[ids.form=='real'].market_id.iloc[0]; n=ids[ids.form=='name'].market_id.iloc[0]
        P=pd.read_sql("SELECT market_id,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport=%s AND market_id=ANY(%s) AND ltp>=1.01",con,params=(sport,[r,n]))
        a=P[P.market_id==r].drop(columns='market_id').drop_duplicates(); b=P[P.market_id==n].drop(columns='market_id').drop_duplicates(); same=len(a.merge(b,on=['sel','ts','ltp']))
        print(f"  sample {sport} {mon}: real prints {len(a)}, other {len(b)}, same {same}",flush=True)
O=pd.DataFrame(out); print("\n"+O.to_string(index=False)); con.close()
print(f"\n== SURVIVORS: check, not a price test\ntotal {time.time()-T0:.0f}s")
PY
