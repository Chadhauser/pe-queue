#!/bin/bash
# 587 (Sun 15 Nov 2026, 16:15). Two readings before the fix:
#  A. loader_core.py (the BASIC-plan loader): where it writes bf_hist_result and whether it does so for every sport or Soccer only;
#     the disk guard constant (loader.log still says "under 20 GB free" — 579's change to 10 GB did not land).
#  B. Postgres is dying on large queries ("server closed the connection unexpectedly" three times today): kernel OOM kills? memory settings?
set -o pipefail
R=/root/pe-queue/reports/loader_core_2026-11-15.md
{
echo "# loader_core.py and Postgres memory — $(date -u '+%F %H:%M') UTC (job 587)"; echo
echo "## A. loader_core.py ($(wc -l < /root/pe-hist/loader_core.py) lines)"; echo '```'
grep -n "bf_hist_result\|bf_hist_other\|WINNER\|status\|sport\|Soccer\|SPORT\|GB\|free\|statvfs\|exit(75)\|GetMyData\|plan\|def \|INSERT\|marketType\|fileTypeCollection" /root/pe-hist/loader_core.py | grep -v "^[0-9]*:\s*#" | cut -c1-230
echo '```'
echo "## A2. bf_hist_other columns and a non-Soccer sample"; echo '```'
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
c=psycopg2.connect(creds.pg_local(),sslmode='disable').cursor(); c.execute("SET statement_timeout='120s'")
c.execute("select column_name from information_schema.columns where table_name='bf_hist_other' order by ordinal_position"); print("bf_hist_other:",[r[0] for r in c.fetchall()])
c.execute("select * from bf_hist_other where sport='Tennis' limit 2"); print("tennis sample:",c.fetchall())
c.execute("select indexdef from pg_indexes where tablename in ('bf_hist_other','bf_hist_result')"); print("indexes:",[r[0][:120] for r in c.fetchall()])
c.execute("select sport, status, count(*) from bf_hist_months group by 1,2 order by 1,2") if False else None
for t in ('bf_hist_months','bf_hist_files'):
    try: c.execute(f"select * from {t} order by 1 limit 40"); print(t,":",c.fetchall())
    except Exception: c.connection.rollback()
PY
echo '```'
echo "## B. Postgres memory"; echo '```'
free -m | head -2; echo; grep -i "out of memory\|oom-kill\|Killed process" /var/log/kern.log /var/log/syslog 2>/dev/null | tail -8 | cut -c1-200; dmesg 2>/dev/null | grep -i "killed process\|out of memory" | tail -6 | cut -c1-200; journalctl -k --since "-24h" 2>/dev/null | grep -i "killed process\|out of memory" | tail -6 | cut -c1-200
echo; psql "$(python3 -c "import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds; print(creds.pg_local())")" -At -c "show shared_buffers; show work_mem; show maintenance_work_mem; show max_connections; show effective_cache_size;" 2>&1 | tr '\n' ' '; echo
tail -20 /var/log/postgresql/*.log 2>/dev/null | grep -i "terminated\|signal\|out of memory\|FATAL" | tail -8 | cut -c1-200
ps -eo rss,comm --sort=-rss | head -12
echo '```'
} > $R 2>&1
cd /root/pe-queue && git add reports/loader_core_2026-11-15.md && git commit -q -m "587: loader core and postgres memory reading" && git pull -q --no-rebase --no-edit && git push -q && echo pushed
echo "587 done"
