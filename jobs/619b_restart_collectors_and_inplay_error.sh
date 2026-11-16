#!/bin/bash
# 619b (Mon 16 Nov 2026). After the migration: ip_tape, liq_sample, xx_tape, monitor_ht, espn, xg, brain and the goal monitor are not
# running, bookie_v2 shows 2 processes, and fairprice_inplay.py exited 1 for every sport in 615. Find how each collector is started
# (cron, keepalive, watchdog scripts), start the missing ones (never late_over / lo_live / anything with placeOrders), keep ONE bookie_v2,
# and capture the in-play engine error. Writes reports/restart_collectors.md.
R=/root/pe-queue/reports/restart_collectors.md
{
echo "# Restart collectors — $(date -u '+%F %H:%M') UTC"; echo
echo "## bookie_v2 processes"; ps -eo pid,lstart,args | grep '[b]ookie_v2' | sed 's/^/    /'
n=$(pgrep -fc 'bookie_v2.py'); if [ "$n" -gt 1 ]; then
  # keep the oldest python process, stop the rest (a wrapper shell + python counts as 2; only kill extra python3 processes)
  py=$(pgrep -f 'python3?[^ ]* .*bookie_v2.py' | sort -n); keep=$(echo "$py" | head -1); extra=$(echo "$py" | tail -n +2)
  [ -n "$extra" ] && { kill $extra; echo "- stopped duplicate bookie_v2 python pids: $extra (kept $keep)"; } || echo "- 2 matches are a wrapper + one python: fine"
fi
echo; echo "## Where each collector is started"
for p in ip_tape liq_sample xx_tape monitor_ht espn xg_ brain goal_monitor goal_signal stream_client sports_team; do
  echo "### $p"; crontab -l 2>/dev/null | grep -v '^#' | grep -i "$p" | sed 's/^/    cron: /' | head -3
  grep -rlE "nohup.*$p|$p.*&$" /root/pe-*/ /root/*.sh 2>/dev/null | grep -E '\.sh$' | head -3 | sed 's/^/    script: /'
done
echo; echo "## Watchdog / keepalive scripts in cron"; crontab -l 2>/dev/null | grep -v '^#' | grep -iE 'watchdog|keepalive|ensure|supervis|break_check' | sed 's/^/    /'
echo; echo "## Running each watchdog once"
crontab -l 2>/dev/null | grep -v '^#' | grep -iE 'watchdog|keepalive|ensure|supervis' | grep -viE 'late_over|lo_live' | sed -E 's/^([^ ]+ +){5}//' | while read -r cmd; do
  echo "- $cmd"; timeout 120 bash -c "$cmd" >/dev/null 2>&1; echo "  exit $?"
done
sleep 30
echo; echo "## Process counts now"
for p in stream_client ip_tape liq_sample xx_tape bookie_v2 monitor_ht sports_team espn xg brain goal late_over lo_live; do echo "- $p: $(pgrep -fc $p)"; done
echo; echo "## In-play engine error (615)"
cd /root/pe-sports/team 2>/dev/null || cd /root/pe-sports
f=$(ls /root/pe-sports/*/fairprice_inplay.py /root/pe-sports/fairprice_inplay.py 2>/dev/null | head -1); echo "file: $f"
[ -n "$f" ] && FP_SPORTS=Soccer timeout 600 python3 "$f" Soccer 2>&1 | tail -25 | sed 's/^/    /'
} > $R 2>&1
cd /root/pe-queue && git add $R && git commit -qm "619b: restart collectors" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q && echo pushed
