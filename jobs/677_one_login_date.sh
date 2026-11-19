#!/bin/bash
# 677 (Thu 19 Nov 2026). READ ONLY. One successful login in 14 days came from 158.220.81.221. When was it, how long, and is that
# address this server itself or another machine? Nothing is changed.
R=/root/pe-queue/reports/login_677.md
{ echo "# 677 - $(date -u '+%F %H:%M') UTC"; echo '```'
echo "this server's own addresses: $(hostname -I)"
echo "-- every record of 158.220.81.221"
( journalctl -u ssh -u sshd --since "30 days ago" --no-pager 2>/dev/null; zcat -f /var/log/auth.log* 2>/dev/null ) | grep "158.220.81.221" | sort -u | head -20 | cut -c1-200
last -i -F 2>/dev/null | grep "158.220.81.221" | cut -c1-120
echo "-- every record of 51.219.246.98 (accepted only)"
journalctl -u ssh -u sshd --since "30 days ago" --no-pager 2>/dev/null | grep "Accepted" | grep "51.219.246.98" | cut -c1-120
echo "-- what ran in the ten minutes after that login (shell history has no times; process accounting if present)"
command -v lastcomm >/dev/null && echo "process accounting present" || echo "no process accounting on this server"
echo '```'; } > $R 2>&1
cd /root/pe-queue && git add $R; git commit -qm "677: one login date" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
