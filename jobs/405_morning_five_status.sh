#!/bin/bash
# 351: THE FIVE LIVE JOBS — one status line each with real numbers (Peter's read-first-five, 5 Nov). Report only.
# 405 (watchman fix of 351): coach_tape has no ts column (UndefinedColumn at line 30 of the job, stopped the python before the heartbeats section); now filters on tape_date.
set -o pipefail
echo "== 4. BASIC history loader (local)"; pgrep -af "pe-hist/loader" | sed 's/postgres[^ ]*/<dsn>/g' | head -2; tail -8 /root/pe-hist/loader.log 2>/dev/null | sed -E 's#postgres(ql)?://[^ ]*#<dsn>#g' | cut -c1-200
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
L=psycopg2.connect(creds.pg_local()); c=L.cursor()
c.execute("select sport, count(*) filter (where status='DONE'), count(*), coalesce(sum(loaded),0) from bf_hist_months group by 1 order by 1"); print("months by sport (done, owned, files):",c.fetchall())
c.execute("select sport, count(distinct market_id), min(market_time)::date, max(market_time)::date from bf_hist_other group by 1"); print("bf_hist_other:",c.fetchall())
c.execute("select count(*) from bf_hist_other where ts > now() - interval '24 hours' or market_time is null");
c.execute("select pg_size_pretty(pg_database_size(current_database()))"); print("local DB size:",c.fetchone()[0])
c.execute("select relname, pg_size_pretty(pg_total_relation_size(oid)) from pg_class where relkind='r' and relnamespace='public'::regnamespace order by pg_total_relation_size(oid) desc limit 8"); print(c.fetchall())
for t in ('fd_matches','af_player_stats','af_fixtures'):
    try: c.execute(f"select count(*) from {t}"); print(t, c.fetchone()[0])
    except Exception as e: L.rollback(); print(t,"missing")
c.execute("select season, count(*) from af_fixtures group by 1 order by 1"); print("af_fixtures by season:",c.fetchall())
R=psycopg2.connect(creds.pg_railway(), sslmode='require'); r=R.cursor(); r.execute("SET statement_timeout='120s'")
print("== 2. cross-exchange recorder (Smarkets/Matchbook rows last 24h)")
for t in ('xx_quotes','xx_samples','xx_ticks','cross_exchange','xx_recorder'):
    try: r.execute(f"select count(*), min(ts), max(ts) from {t} where ts > now()-interval '24 hours'"); print(t, r.fetchone())
    except Exception: R.rollback()
r.execute("select table_name from information_schema.tables where table_name like 'xx%' or table_name like '%smarkets%' or table_name like '%matchbook%'"); print("xx tables:",[x[0] for x in r.fetchall()])
print("== 1. post-goal fade paper")
r.execute("select table_name from information_schema.tables where table_name like '%fade%'"); fts=[x[0] for x in r.fetchall()]; print("fade tables:",fts)
for t in fts[:4]:
    try: r.execute(f"select count(*), round(avg(pnl_per_10)::numeric,3), min(entry_ts)::date, max(entry_ts)::date from {t}"); print(t, r.fetchone())
    except Exception: R.rollback()
print("== 5. goal signal"); r.execute("select count(*), count(fav_price), count(home_sot) from goal_live_predictions where captured_at > now()-interval '24 hours'"); print("predictions 24h (rows, with fav price, with SOT):",r.fetchone())
r.execute("select count(*), count(real_price) from goal_alerts where sent_at > now()-interval '24 hours'"); print("alerts 24h (n, with real price):",r.fetchone())
r.execute("select count(*) from coach_tape where tape_date >= current_date-1"); print("coach_tape rows since yesterday:",r.fetchone()[0])
print("== heartbeats");
for t in ('racing_heartbeat','liq_heartbeat','player_heartbeat','preoff_scalp_heartbeat','stream_heartbeat'):
    try: r.execute(f"select round(extract(epoch from now()-max(last_seen))/60) from {t}"); print(t, r.fetchone()[0],"min")
    except Exception: R.rollback(); print(t,"n/a")
PY
echo "== racing heartbeat owner"; grep -l "racing_heartbeat" /root/pe-*/*.py /root/pe-logger/*.py 2>/dev/null | head -3; pgrep -af "racing" | sed 's/postgres[^ ]*/<dsn>/g' | head -5
