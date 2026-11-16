#!/bin/bash
# 621 (Mon 16 Nov 2026, 18:05). Three checks, one report (reports/stale_services.md):
#  1. Is 613 (execution_methods.py, background, 3h cap) still alive? Log tail.
#  2. Why espn, xg, brain (monitor_ht / stats_collector) and the goal monitor stay down after the 14:56 host restart:
#     find what writes each heartbeat, run its launcher once in the foreground for 25 s and keep stderr.
#  3. The in-play engine died on "server closed the connection" (fairprice_inplay.py:32): postgres log around it,
#     memory settings, and the query at that line.
# Read-and-restart only. Never touches late_over / lo_live (REAL_MONEY_OFF stays).
R=/root/pe-queue/reports/stale_services.md
{
echo "# Stale services check — $(date -u '+%F %H:%M') UTC"; echo
echo "## 1. Job 613 (execution methods)"
pgrep -af execution_methods.py | grep -v pgrep || echo "NOT running"
echo '```'; tail -15 /root/pe-sports/team/execution_methods.log 2>&1; echo '```'
echo
echo "## 2. Stale heartbeats"
for name in espn xg brain monitor_ht stats_collector goal_monitor goal_signal; do
  echo "### $name"
  echo "- processes: $(pgrep -f "$name" | wc -l)"
  echo "- scripts that mention heartbeat '$name':"
  grep -rlE "heartbeat.*['\"]$name['\"]|['\"]$name['\"].*heartbeat" /root/pe-brain /root/pe-sports /root/pe-espn /root/pe-xg /root/pe-goal* 2>/dev/null | grep -vE '\.bak|/jobs/' | head -5 | sed 's/^/    /'
done
echo
echo "### pe-brain launchers"
ls -la /root/pe-brain/*.sh 2>&1 | head
for s in /root/pe-brain/run_monitor_ht.sh /root/pe-brain/run_stats_collector.sh; do
  [ -f "$s" ] || continue
  echo "#### $s"; echo '```'; cat "$s"; echo '```'
  echo "foreground 25 s:"; echo '```'; timeout 25 bash "$s" 2>&1 | tail -20; echo "exit $?"; echo '```'
done
echo "### other launchers mentioning espn / xg / goal"
ls /root/pe-*/ 2>/dev/null | head -0
for f in $(ls /root/pe-*/run_*.sh /root/pe-*/*/run_*.sh 2>/dev/null | grep -iE 'espn|xg|goal'); do
  echo "#### $f"; echo '```'; cat "$f"; echo '```'
  echo "foreground 25 s:"; echo '```'; timeout 25 bash "$f" 2>&1 | tail -20; echo '```'
done
echo "### last log lines"
for l in $(ls -t /root/pe-brain/*.log /root/pe-espn/*.log /root/pe-xg/*.log /root/pe-sports/*/espn*.log /root/pe-sports/*/xg*.log /root/pe-sports/*/goal*.log 2>/dev/null | head -8); do
  echo "#### $l"; echo '```'; tail -8 "$l"; echo '```'
done
echo
echo "## 3. In-play engine connection drop"
F=$(ls /root/pe-sports/*/fairprice_inplay.py /root/pe-sports/fairprice_inplay.py 2>/dev/null | head -1)
echo "file: $F"; echo '```'; sed -n 20,45p "$F"; echo '```'
echo "postgres settings:"; echo '```'
sudo -u postgres psql -Atc "select name,setting,unit from pg_settings where name in ('shared_buffers','work_mem','maintenance_work_mem','statement_timeout','idle_in_transaction_session_timeout','max_connections','temp_file_limit')" 2>&1
echo '```'
echo "postgres log (crashes, kills, OOM, terminations) today:"; echo '```'
PL=$(ls -t /var/log/postgresql/*.log 2>/dev/null | head -1)
grep -iE 'terminat|killed|out of memory|server process|crash|FATAL|PANIC' "$PL" 2>/dev/null | tail -25
echo '```'
echo "kernel OOM today:"; echo '```'; dmesg -T 2>/dev/null | grep -iE 'out of memory|oom-kill|killed process' | tail -10; journalctl -k --since today 2>/dev/null | grep -iE 'oom|killed process' | tail -10; echo '```'
echo "free -g:"; echo '```'; free -g; echo '```'
} > "$R" 2>&1
cd /root/pe-queue && git add "$R" && git commit -qm "621: 613 status, stale services, in-play connection drop" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
echo "621 done"
