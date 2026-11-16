#!/bin/bash
# 619 (Mon 16 Nov 2026). The VPS migration restarted the host at 14:56; espn, xg, brain, late_over, lo_live and the goal monitor
# did not come back. Restart every stopped collector/monitor EXCEPT anything that can place a real order (placeOrders in its code,
# or late_over / lo_live): those stay off (REAL_MONEY_OFF). Also makes sure the bot (bookie_v2, paper) and recorders are up.
# Writes reports/restart_after_migration.md.
R=/root/pe-queue/reports/restart_after_migration.md
{
echo "# Restart after migration — $(date -u '+%F %H:%M') UTC"; echo
echo "free -g: $(free -g | awk '/Mem/{print $2" GB total, "$7" GB available"}') | nproc $(nproc) | disk free $(df -BG --output=avail / | tail -1)"
echo; echo "## Services (systemd) matching our names"
systemctl list-units --all --type=service --no-legend 2>/dev/null | grep -iE 'pe-|espn|xg|brain|goal|monitor|late|lo_live|bookie|stream|tape|liq|sports|collector' | sed 's/^/    /'
echo; echo "## @reboot cron lines"; crontab -l 2>/dev/null | grep -i '@reboot' | sed 's/^/    /'
echo; echo "## Actions"
for u in $(systemctl list-units --all --type=service --no-legend 2>/dev/null | awk '{print ($1=="●"?$2:$1)}' | grep -iE 'espn|xg|brain|goal|monitor|bookie|stream|tape|liq|sports|collector|late|lo_live'); do
  st=$(systemctl is-active $u); [ "$st" = active ] && continue
  ex=$(systemctl show -p ExecStart --value $u | grep -oE '/[^ ;]+\.py' | head -1)
  if echo "$u" | grep -qiE 'late|lo_live' || { [ -n "$ex" ] && grep -q placeOrders "$ex" 2>/dev/null; }; then echo "- $u: $st — LEFT OFF (can place real orders: ${ex:-name})"; continue; fi
  systemctl restart $u; sleep 5; echo "- $u: was $st, restarted, now $(systemctl is-active $u)"
done
# @reboot lines for non-money processes that are not running
crontab -l 2>/dev/null | grep '@reboot' | sed 's/^@reboot[[:space:]]*//' | while read -r cmd; do
  py=$(echo "$cmd" | grep -oE '[^ ]+\.py' | head -1); [ -z "$py" ] && continue
  echo "$py" | grep -qiE 'late_over|lo_live' && { echo "- @reboot $py: LEFT OFF (real-money bot)"; continue; }
  f=$(echo "$cmd" | grep -oE '/[^ ]+\.py' | head -1); [ -n "$f" ] && grep -q placeOrders "$f" 2>/dev/null && { echo "- @reboot $py: LEFT OFF (placeOrders)"; continue; }
  pgrep -f "$(basename $py)" >/dev/null && continue
  nohup bash -c "$cmd" >/dev/null 2>&1 & sleep 3; echo "- @reboot $py: was not running, started: $(pgrep -f "$(basename $py)" >/dev/null && echo yes || echo NO)"
done
echo; echo "## Process counts now"
for p in stream_client ip_tape liq_sample xx_tape bookie_v2 monitor_ht sports_team espn xg brain goal late_over lo_live; do echo "- $p: $(pgrep -fc $p)"; done
echo; echo "REAL_MONEY_OFF present: $([ -f /root/REAL_MONEY_OFF ] && echo yes || echo NO)"
} > $R 2>&1
cd /root/pe-queue && git add $R && git commit -qm "619: restart after migration" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q && echo pushed
