#!/bin/bash
set -o pipefail
# 499_holdout_census (Finder 2026-11-04, queue item 55c): what price data do we hold that candidates C1-C6 were NOT selected on? Selection data = bf_hist_price seasons 2024 and 2025. Read only; counts and date ranges, no P&L. Local Postgres for history, Railway for the live tape only. Never prints a DSN.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,os,glob,time,psycopg2
sys.path.insert(0,'/root/pe-queue/runner'); import creds
T0=time.time()
def run(cur,label,sql,params=None):
    """Print the rows of one census query; a missing table or timeout is a finding, not a crash."""
    try:
        cur.execute(sql,params)
        rows=cur.fetchall()
        print(f"{label}: {rows if len(rows)<=40 else rows[:40]}",flush=True)
        return rows
    except psycopg2.Error as e:
        print(f"{label}: UNAVAILABLE {type(e).__name__}: {str(e).splitlines()[0][:150]}",flush=True)
        return None
L=psycopg2.connect(creds.pg_local()); L.autocommit=True; l=L.cursor()
l.execute("SET work_mem='64MB'; SET statement_timeout='600s'")
print("== local tables of interest (estimated rows)")
run(l,"tables","""SELECT relname,reltuples::bigint FROM pg_class WHERE relkind IN ('r','p','m') AND relnamespace='public'::regnamespace
 AND (relname ~ '^(bf_hist|af_|goal_|fd_|football_data|hist_|basic_|tn_|racing_results|candidates)' OR relname ~ 'basic|football|closing') ORDER BY 1""")
print("\n== (a) bf_hist_other columns and Soccer market types")
run(l,"columns","SELECT column_name,data_type FROM information_schema.columns WHERE table_name='bf_hist_other' ORDER BY ordinal_position")
ids=run(l,"soccer market-type prefixes (loose index scan)","""WITH RECURSIVE t AS ((SELECT market_id FROM bf_hist_other WHERE sport='Soccer' ORDER BY market_id LIMIT 1)
 UNION ALL SELECT (SELECT market_id FROM bf_hist_other WHERE sport='Soccer' AND market_id>split_part(t.market_id,'|',1)||'}' ORDER BY market_id LIMIT 1) FROM t WHERE t.market_id IS NOT NULL)
 SELECT split_part(market_id,'|',1) FROM t WHERE market_id IS NOT NULL""")
run(l,"bf_hist_other indexes","SELECT indexname,indexdef FROM pg_indexes WHERE tablename='bf_hist_other'")
run(l,"bf_hist_other_files columns","SELECT column_name FROM information_schema.columns WHERE table_name='bf_hist_other_files' ORDER BY ordinal_position")
run(l,"bf_hist_months columns","SELECT column_name FROM information_schema.columns WHERE table_name='bf_hist_months' ORDER BY ordinal_position")
run(l,"fd_matches columns","SELECT column_name FROM information_schema.columns WHERE table_name='fd_matches' ORDER BY ordinal_position")
run(l,"fd_matches by league","SELECT div,count(*),min(season),max(season) FROM fd_matches WHERE div IN ('SP1','SP2') GROUP BY 1")
l.execute("SET statement_timeout='420s'")
print("\n== soccer markets by type and month, sampled by distinct market_id")
run(l,"soccer type x month","""SELECT market_type,to_char(market_time,'YYYY-MM') mth,count(DISTINCT market_id) mkts,count(*) prints,count(*) FILTER (WHERE inplay) ip
 FROM bf_hist_other WHERE sport='Soccer' AND market_type IN ('OVER_UNDER_15','OVER_UNDER_25','BOTH_TEAMS_TO_SCORE','MATCH_ODDS') GROUP BY 1,2 ORDER BY 1,2""")
run(l,"soccer other types","""SELECT market_type,count(DISTINCT market_id),min(market_time)::date,max(market_time)::date FROM bf_hist_other WHERE sport='Soccer' GROUP BY 1 ORDER BY 2 DESC LIMIT 40""")
print("\n== loader output, other tables that may hold prices: names and date spans")
for t,dcol in (('bf_hist_price',None),('goal_timeline','captured_at')):
    if dcol: run(l,f"{t} span",f"SELECT min({dcol}),max({dcol}) FROM {t}")
run(l,"af_fixtures by season","SELECT season,count(*),count(*) FILTER (WHERE status='FT'),min(date(kickoff)),max(date(kickoff)) FROM af_fixtures GROUP BY 1 ORDER BY 1")
run(l,"af_fixtures columns","SELECT column_name FROM information_schema.columns WHERE table_name='af_fixtures' ORDER BY ordinal_position")
run(l,"af_events columns","SELECT column_name FROM information_schema.columns WHERE table_name='af_events' ORDER BY ordinal_position")
run(l,"bf_hist_price columns","SELECT column_name FROM information_schema.columns WHERE table_name='bf_hist_price' ORDER BY ordinal_position")
run(l,"af_price_map columns","SELECT column_name FROM information_schema.columns WHERE table_name='af_price_map' ORDER BY ordinal_position")
print("\n== shapes the candidate jobs depend on")
run(l,"bf_hist_months soccer","SELECT y,m,status,files,loaded FROM bf_hist_months WHERE sport ILIKE 'soccer%' ORDER BY y DESC,m DESC LIMIT 30")
run(l,"OU15 sels","SELECT sel,count(*) FROM bf_hist_other WHERE sport='Soccer' AND market_type='OVER_UNDER_15' GROUP BY 1 ORDER BY 2 DESC LIMIT 6")
run(l,"BTTS sels","SELECT sel,count(*) FROM bf_hist_other WHERE sport='Soccer' AND market_type='BOTH_TEAMS_TO_SCORE' GROUP BY 1 ORDER BY 2 DESC LIMIT 6")
run(l,"one OU15 market","""SELECT market_id,event_id,event_name,market_time,country,sel,ts,ltp,inplay FROM bf_hist_other WHERE sport='Soccer' AND market_type='OVER_UNDER_15' AND market_id=(SELECT market_id FROM bf_hist_other WHERE sport='Soccer' AND market_type='OVER_UNDER_15' LIMIT 1) ORDER BY ts LIMIT 6""")
run(l,"OU15 median gap sec between in-play prints per market/sel","""SELECT percentile_cont(ARRAY[0.5,0.9,0.99]) WITHIN GROUP (ORDER BY g) FROM (SELECT extract(epoch FROM ts-lag(ts) OVER (PARTITION BY market_id,sel ORDER BY ts)) g FROM bf_hist_other WHERE sport='Soccer' AND market_type='OVER_UNDER_15' AND inplay AND market_time>='2026-09-01' AND market_time<'2026-09-08') x WHERE g IS NOT NULL""")
run(l,"goal_timeline columns","SELECT column_name FROM information_schema.columns WHERE table_name='goal_timeline' ORDER BY ordinal_position")
run(l,"goal_timeline leagues 140/141 by month","""SELECT league_id,to_char(captured_at,'YYYY-MM'),count(DISTINCT fixture_id),count(*) FROM goal_timeline WHERE league_id IN (140,141) GROUP BY 1,2 ORDER BY 1,2""")
run(l,"af_fixtures league ids and 2026 FT with events, 140/141","""SELECT league_id,season,count(*) FILTER (WHERE status='FT'),count(*) FILTER (WHERE status='FT' AND events_done) FROM af_fixtures WHERE league_id IN (140,141) GROUP BY 1,2 ORDER BY 1,2""")
run(l,"fd SP2 odds fill by season","""SELECT season,count(*),count(p_o25),count(b365o25),count(raw) FROM fd_matches WHERE div='SP2' GROUP BY 1 ORDER BY 1""")
run(l,"fd raw keys one row","""SELECT raw FROM fd_matches WHERE div='SP2' AND season='2526' LIMIT 1""")
L.close()
print("\n== (b) liq_sample on Railway")
try:
    R=psycopg2.connect(creds.pg_railway()); R.autocommit=True; r=R.cursor(); r.execute("SET work_mem='64MB'; SET statement_timeout='300s'")
    run(r,"liq_sample columns","SELECT column_name FROM information_schema.columns WHERE table_name='liq_sample' ORDER BY ordinal_position")
    run(r,"liq_sample span","SELECT min(ts),max(ts) FROM liq_sample")
    run(r,"liq_sample markets","SELECT mkt,count(DISTINCT event_name) FROM liq_sample WHERE mkt IN ('MO','BTTS','OU15','OU25') GROUP BY 1")
    run(r,"BTTS sels on the tape","SELECT DISTINCT sel FROM liq_sample WHERE mkt='BTTS' LIMIT 6")
    run(r,"La Liga / Segunda on the tape","SELECT competition,count(DISTINCT event_name) FROM liq_sample WHERE competition ILIKE '%spanish%' OR competition ILIKE '%liga%' OR competition ILIKE '%segunda%' GROUP BY 1 ORDER BY 2 DESC LIMIT 12")
    run(r,"railway goal_timeline span","SELECT min(captured_at),max(captured_at) FROM goal_timeline")
    R.close()
except psycopg2.Error as e:
    print(f"railway UNAVAILABLE {type(e).__name__}",flush=True)
print("\n== (d) FTS xlsx on the box")
hits=[p for root in ('/root','/home','/data','/mnt','/srv') for p in glob.glob(root+'/**/*FTS*.xlsx',recursive=True)]
print(f"FTS xlsx files found: {len(hits)}",hits[:5])
print(f"\ntotal {time.time()-T0:.0f}s")
print("\n== SURVIVORS\nnot applicable: census, no P&L")
PY
