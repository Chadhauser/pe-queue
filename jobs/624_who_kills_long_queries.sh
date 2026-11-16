#!/bin/bash
# 624 (Mon 16 Nov 2026, 19:25). 623: the in-play engine's bf_hist_other scan (172M rows) is cut off after ~254 s with
# "server closed the connection" and no crash in the postgres log. Suspect something terminates long queries
# (the client sees exactly that on pg_terminate_backend). Find it. Read only. Report: reports/fix_624.md
R=/root/pe-queue/reports/fix_624.md
{
echo "# 624 who kills long queries — $(date -u '+%F %H:%M') UTC"; echo
echo "## postgres log: terminations today"; echo '```'
grep -a -E 'terminating connection|canceling statement|terminated by signal' /var/log/postgresql/postgresql-18-main.log | grep -a "$(date '+%Y-%m-%d')" | grep -av ' 11:06:0' | tail -15
echo '```'
echo "## scripts and cron that terminate or cancel backends"; echo '```'
crontab -l | grep -nE 'terminate|cancel|kill|long_q|pg_'
grep -rlE 'pg_terminate_backend|pg_cancel_backend' /root/pe-*/ /root/*.sh /root/*.py 2>/dev/null | grep -vE '/jobs/|\.bak|/repo/jobs/' | head -20
echo '```'
for f in $(grep -rlE 'pg_terminate_backend|pg_cancel_backend' /root/pe-*/ /root/*.sh /root/*.py 2>/dev/null | grep -vE '/jobs/|\.bak|/repo/jobs/' | head -6); do
  echo "### $f"; echo '```'; grep -nE -B3 -A3 'pg_terminate_backend|pg_cancel_backend' "$f" | head -30; echo '```'
  echo "started by: $(crontab -l | grep -F "$(basename $f)" | head -2)"
done
echo "## database-side limits"; echo '```'
sudo -u postgres psql -Atc "select rolname, rolconfig from pg_roles where rolconfig is not null"
sudo -u postgres psql -Atc "select datname, setconfig from pg_db_role_setting s left join pg_database d on d.oid=s.setdatabase"
sudo -u postgres psql -Atc "select name,setting from pg_settings where name in ('tcp_keepalives_idle','client_connection_check_interval','transaction_timeout','idle_session_timeout','max_parallel_workers_per_gather','temp_tablespaces')"
echo '```'
echo "## how creds.pg_local connects (host/port only)"; echo '```'
python3 -c "import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds; from psycopg2.extensions import parse_dsn; d=parse_dsn(creds.pg_local()); print({k:d.get(k) for k in ('host','port','dbname','user','options','keepalives')})"
echo '```'
} > "$R" 2>&1
cd /root/pe-queue && git add "$R" && git commit -qm "624: who kills long queries" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
echo "624 done"
