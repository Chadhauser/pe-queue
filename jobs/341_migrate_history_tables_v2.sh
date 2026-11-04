#!/bin/bash
# 341 (339 re-issued after 340 put PG 18 on the box; 339 ran under 17 and copied nothing): MIGRATE HISTORY TABLES Railway -> local Postgres, streaming (pg_dump | psql, no dump file on disk). Resumable: a table
# already present locally with the same row count is skipped; after ~150 min it exits 75 so the runner re-polls and it
# continues. Nothing is dropped on Railway here (that is a later job, after the Finder has run against the local copy).
set -o pipefail
export PATH=/usr/lib/postgresql/18/bin:$PATH   # Railway is PG 18.6: dump with the 18 client
FAILS=0
set -a; . /root/.pe_local_pg.env; set +a
RAIL=$(python3 -c "import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds; print(creds.pg_railway())")
[ -n "$RAIL" ] && [ -n "$PE_LOCAL_PG" ] || { echo "missing DSN"; exit 1; }
START=$(date +%s)
# order: the tables the tests read most, biggest last. Tape tables (ip_tape, liq_sample, stream_ticks) are NOT here: they move with their recorders (job 340).
TABLES="af_fixtures af_events af_stats af_price_map af_lineups af_lineups_done af_odds bf_hist_price bf_hist_other racing_bsp fair_price_games fair_price_results goal_timeline goal_stats_live goal_live_predictions goal_alerts goal_alerts_real coach_tape coach_path grid_cells_v3 grid_survivors_v3 boring_results_v3 preoff_scalp_paper"
for t in $TABLES; do
  if [ $(( $(date +%s) - START )) -gt 9000 ]; then echo "time budget reached, re-poll"; exit 75; fi
  exists=$(psql "$RAIL" -Atqc "select to_regclass('public.$t') is not null" 2>/dev/null)
  [ "$exists" = "t" ] || { echo "-- $t: not on Railway, skip"; continue; }
  rn=$(psql "$RAIL" -Atqc "select reltuples::bigint from pg_class where relname='$t'")
  ln=$(psql "$PE_LOCAL_PG" -Atqc "select case when to_regclass('public.$t') is null then -1 else (select count(*) from $t) end" 2>/dev/null || echo -1)
  if [ "$ln" -ge 0 ] && [ "$rn" -gt 0 ] && [ $(( ln * 100 / (rn + 1) )) -ge 98 ]; then echo "-- $t: already local ($ln rows), skip"; continue; fi
  echo "-- $t: copying (railway est $rn rows) $(date -u +%H:%M:%S)"
  psql "$PE_LOCAL_PG" -qc "DROP TABLE IF EXISTS $t" 
  if pg_dump --version >/dev/null && pg_dump --no-owner --no-acl --no-comments -t "public.$t" "$RAIL" | psql "$PE_LOCAL_PG" -q -v ON_ERROR_STOP=1; then
    ln=$(psql "$PE_LOCAL_PG" -Atqc "select count(*) from $t"); echo "   done: local $ln rows $(date -u +%H:%M:%S)"
  else
    echo "   FAILED $t (see above); continuing with the next table"; FAILS=$((FAILS+1)); psql "$PE_LOCAL_PG" -qc "DROP TABLE IF EXISTS $t"
  fi
done
echo "== local inventory"; psql "$PE_LOCAL_PG" -Atc "select relname||'  '||pg_size_pretty(pg_total_relation_size(oid)) from pg_class where relkind='r' and relnamespace='public'::regnamespace order by pg_total_relation_size(oid) desc"
echo "== disk"; df -h / | tail -1
echo "tables failed: $FAILS"; [ "$FAILS" -eq 0 ]
