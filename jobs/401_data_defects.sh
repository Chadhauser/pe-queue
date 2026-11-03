#!/bin/bash
# 324: two data defects the Finder found, diagnosed (report only): (1) ip_tape holds only ~6 days (brief said since Sept) — find what
# prunes it and liq_sample, and the disk/table sizes, so retention can be raised to 60 days; (2) goal_live_predictions has had NULL
# home_sot/away_sot/home_da/away_da since 27 Oct — find which process writes them and why it stopped (the live-key switch on 27 Oct
# touched 9 files; likely the stats recorder lost its source). Nothing is changed here.
# 401 (watchman fix of 324): last line's `[ -f "$l" ] && {...}` returned 1 for the unmatched glob /root/pe-goal*/*.log, so the job exited 1 after printing everything; now uses if/fi and exits 0.
echo "== disk"; df -h / | tail -1
echo "== table sizes"; python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require'); k=c.cursor()
k.execute("SELECT relname, pg_size_pretty(pg_total_relation_size(relid)) FROM pg_catalog.pg_statio_user_tables ORDER BY pg_total_relation_size(relid) DESC LIMIT 12"); print(k.fetchall())
k.execute("SELECT pg_size_pretty(pg_database_size(current_database()))"); print('db total',k.fetchone())
for t,col in (('ip_tape','ts'),('liq_sample','ts'),('stream_ticks','ts_recv'),('goal_live_predictions','captured_at'),('goal_stats_live','captured_at')):
    k.execute(f"SELECT min({col})::date, max({col})::date, count(*) FROM {t}"); print(t,k.fetchone())
k.execute("SELECT max(captured_at) FROM goal_live_predictions WHERE home_sot IS NOT NULL"); print('last non-null SOT in goal_live_predictions:',k.fetchone())
k.execute("SELECT max(captured_at), count(*) FILTER (WHERE captured_at>now()-interval '1 day') FROM goal_stats_live"); print('goal_stats_live last / rows 24h:',k.fetchone())
PY
echo "== who prunes ip_tape / liq_sample / stream_ticks"; grep -rn -i -E "delete from (ip_tape|liq_sample|stream_ticks)|retention|interval '[0-9]+ day" /root/pe-* /root/pe-queue/runner /etc/cron* 2>/dev/null | grep -v "/jobs/" | grep -v "\.log" | head -30
echo; echo "== crontab"; crontab -l
echo; echo "== who writes home_sot/home_da into goal_live_predictions"; grep -rln -E "home_sot|home_da" /root/pe-* 2>/dev/null | grep -v pe-queue/jobs | head; for f in $(grep -rln -E "INSERT INTO goal_live_predictions|goal_live_predictions" /root/pe-* 2>/dev/null | grep -v pe-queue/jobs | head -5); do echo "--- $f"; grep -n -E "home_sot|home_da|stats_json|statistics|SELECT .* FROM goal_stats_live" "$f" | head -12; done
echo; echo "== stats recorder process + its last log lines"; ps -eo pid,etime,cmd | grep -E "stats_recorder|espn_recorder|goal_engine|goal_signal" | grep -v grep; for l in /root/pe-stats/*.log /root/pe-goal*/*.log; do if [ -f "$l" ]; then echo "--- $l"; tail -5 "$l"; fi; done 2>/dev/null
exit 0
