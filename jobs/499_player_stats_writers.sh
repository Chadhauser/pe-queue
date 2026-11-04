#!/bin/bash
set -o pipefail
# 499_player_stats_writers (Finder 2026-11-04, queue item 62): read only. af_player_stats grew after this run's loader exited at about 21:22 UTC: who is writing? Done marks per 5 minutes, and any session on the local database touching the table. No key or DSN printed; query text is cut short and only shown if it names the table.
python3 - <<'PY' 2>&1
import sys,psycopg2
sys.path.insert(0,'/root/pe-queue/runner'); import creds
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; k=con.cursor(); k.execute("SET statement_timeout='120s'")
k.execute("SELECT now()"); print("now:",k.fetchone()[0])
k.execute("SELECT date_trunc('hour',fetched_at)+floor(extract(minute FROM fetched_at)/5)*interval '5 min' b,count(*),sum(n) FROM af_player_stats_done GROUP BY 1 ORDER BY 1 DESC LIMIT 14")
for r in k.fetchall(): print(" ",*r)
k.execute("SELECT count(*) FROM af_player_stats_done"); print("done marks:",k.fetchone()[0])
k.execute("SELECT pid,application_name,client_addr,backend_start,state,left(query,70) FROM pg_stat_activity WHERE query ILIKE '%af_player_stats%' AND pid<>pg_backend_pid()")
print("sessions on the table:",k.fetchall())
con.close()
PY
