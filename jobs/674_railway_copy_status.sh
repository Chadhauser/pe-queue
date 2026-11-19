#!/bin/bash
# 674 (Thu 19 Nov 2026). READ ONLY. Where is the Railway final copy (673)? Process, log, the table so far, and row counts of what landed.
R=/root/pe-queue/reports/railway_674.md
{ echo "# 674 - $(date -u '+%F %H:%M') UTC"; echo '```'
echo "process:"; pgrep -fa '[f]inal_copy' | cut -c1-100 || echo "  not running"
echo "log tail:"; tail -15 /root/pe-migrate/final_copy.log 2>&1 | cut -c1-300
echo "disk:"; df -h / | tail -1
echo '```'; echo; cat /root/pe-queue/reports/railway_673.md 2>&1
echo; echo '```'
python3 - <<'PY'
import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds, psycopg2
c=psycopg2.connect(creds.pg_local(),sslmode='disable').cursor()
c.execute("select relname, n_live_tup, pg_size_pretty(pg_total_relation_size(relid)) from pg_stat_user_tables where schemaname='railway_final' order by 1"); print("copies on this server so far:"); [print("  ",r) for r in c.fetchall()]
PY
echo '```'; } > $R 2>&1
cd /root/pe-queue && git add $R reports/railway_673.md 2>/dev/null; git commit -qm "674: railway copy status" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
