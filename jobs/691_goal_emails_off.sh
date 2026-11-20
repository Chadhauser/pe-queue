#!/bin/bash
# 691 (Fri 20 Nov 2026 18:34, Peter: goal signal emails are stale by the time he reads them and the signal is not validated).
# Switches off the goal alert EMAIL only (set up 13 Nov). The monitor keeps recording alerts to the database. Nothing deleted.
R=/root/pe-queue/reports/goal_emails_691.md
crontab -l > /root/pe-queue-state/crontab_before_691.txt
crontab -l | sed -E 's|^(\*/2 \* \* \* \* /root/pe-sports/team/goal_alert_mail\.sh.*)$|#STOPPED-691 \1|' | crontab -
{ echo "# Goal alert emails switched off - $(date -u '+%F %H:%M') UTC"; echo
  echo "- live timer lines for the goal email: $(crontab -l | grep -v '^#' | grep -c goal_alert_mail)"
  echo "- stopped line kept: $(crontab -l | grep -c '^#STOPPED-691')"
  echo "- goal monitor still running: $(pgrep -fc '[m]onitor_ht' ) process(es)"
  echo "- timer list before the change saved at /root/pe-queue-state/crontab_before_691.txt"; } > $R
cd /root/pe-queue && git add "$R" && git commit -qm "691: goal alert emails off" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
