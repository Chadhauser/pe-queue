#!/bin/bash
# 593 (Sun 15 Nov 2026, 18:15). Progress peek on the results backfill (589): is it alive, how far, any warning.
echo "process: $(pgrep -fa results_backfill.py | cut -c1-80)"; echo "--- log tail:"; tail -12 /root/pe-hist/results_backfill.log | cut -c1-200
echo "--- results by sport now:"; python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
c=psycopg2.connect(creds.pg_local(),sslmode='disable').cursor(); c.execute("SET statement_timeout='120s'"); c.execute("select sport, count(*) from bf_hist_result group by 1 order by 2 desc"); print(c.fetchall())
PY
df -h / | tail -1; free -m | awk '/Mem:/{print "free MB",$7}'
{ echo "# backfill progress $(date -u '+%F %H:%M')"; echo '```'; pgrep -fa results_backfill.py | cut -c1-80; tail -12 /root/pe-hist/results_backfill.log | cut -c1-200; echo '```'; } > /root/pe-queue/reports/backfill_progress.md
cd /root/pe-queue && git add reports/backfill_progress.md && git commit -qm "backfill progress" && git pull -q --no-rebase --no-edit && git push -q && echo pushed
echo "593 done"
