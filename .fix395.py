CTE=("WITH t AS (SELECT *,total_matched::float8 tm0,max(total_matched::float8) OVER (PARTITION BY market_id ORDER BY ts ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) hi FROM cricket_fav_tape), "
     "c AS (SELECT * FROM t WHERE hi IS NULL OR tm0 IS NULL OR tm0>=hi*0.999) ")
NOTE="# FIX 2026-11-07, the one fix: replay rows dropped. This REST tape replays old book states, total_matched falling under the market's earlier high, 17% of in-play rows; job 497 found the same on ip_tape. A row is kept only if total_matched is at or above 0.999 of the market's high so far. The first run did not do this; its numbers are in the report.\n"
def sw(t,a,b):
    assert t.count(a)==1,a
    return t.replace(a,b)
p='jobs/499_cricket_touch.sh.wip'; t=open(p).read()
t=sw(t,"python3 - \"$@\" <<'PY'",NOTE+"python3 - \"$@\" <<'PY'")
t=sw(t,'''A=pd.read_sql("SELECT ts,market_id,event_name ev,competition comp,start_time mt,sel_name sel,ltp::float8 ltp,back_px::float8 bp,lay_px::float8 lp,total_matched::float8 tm FROM cricket_fav_tape WHERE NOT inplay''','''CTE="%s"
print("replay rows dropped, pre-off and in play:",pd.read_sql("WITH t AS (SELECT inplay,total_matched::float8 tm0,max(total_matched::float8) OVER (PARTITION BY market_id ORDER BY ts ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) hi FROM cricket_fav_tape) SELECT inplay,count(*) n,sum((tm0<hi*0.999)::int) replay FROM t GROUP BY 1",rc).to_dict('records'),flush=True)
A=pd.read_sql(CTE+"SELECT ts,market_id,event_name ev,competition comp,start_time mt,sel_name sel,ltp::float8 ltp,back_px::float8 bp,lay_px::float8 lp,total_matched::float8 tm FROM c WHERE NOT inplay''' % CTE)
t=sw(t,'''B=pd.read_sql("SELECT DISTINCT ON (market_id,sel_name) market_id,sel_name sel,ltp::float8 ltp,ts FROM cricket_fav_tape WHERE inplay''','''B=pd.read_sql(CTE+"SELECT DISTINCT ON (market_id,sel_name) market_id,sel_name sel,ltp::float8 ltp,ts FROM c WHERE inplay''')
open(p,'w').write(t)
p='jobs/499_cricket_touch_inplay.sh.wip'; t=open(p).read()
t=sw(t,"python3 - \"$@\" <<'PY'",NOTE+"python3 - \"$@\" <<'PY'")
t=sw(t,'''A=pd.read_sql("SELECT ts,market_id,event_name ev,start_time mt,sel_name sel,ltp::float8 ltp,back_px::float8 bp,lay_px::float8 lp FROM cricket_fav_tape WHERE inplay ORDER BY''','''A=pd.read_sql("%sSELECT ts,market_id,event_name ev,start_time mt,sel_name sel,ltp::float8 ltp,back_px::float8 bp,lay_px::float8 lp FROM c WHERE inplay ORDER BY''' % CTE)
open(p,'w').write(t)
print('patched')
