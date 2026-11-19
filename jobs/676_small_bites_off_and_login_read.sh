#!/bin/bash
# 676 (Thu 19 Nov 2026, CEO chat 15:19).
#  1. Switch off the price-move paper rule ("small bites") as ordered: it failed the proof gate (a half is negative). Keepalive line
#     disabled, process stopped, STOPPED marker written. Its table stays; nothing is deleted. Crontab backed up first.
#  2. Remote login: READ ONLY - the settings and the login record. Nothing about login is changed here.
R=/root/pe-queue/reports/login_676.md; T=/root/pe-sports/team
{ echo "# 676 - $(date -u '+%F %H:%M') UTC"; echo '```'
echo "== 1. small bites off"
crontab -l > /root/crontab.bak_676
crontab -l | sed '/small_bites_live/ s/^\([^#]\)/#STOPPED-676 \1/' | crontab -
pkill -f '[s]mall_bites_live.py'; pkill -f '[r]un_small_bites_live.sh'; sleep 2
echo "STOPPED 19 Nov 2026 (676): failed the proof gate, a half is negative" > $T/small_bites.STOPPED
crontab -l | grep -n "small_bites" | cut -c1-150; echo "processes left: $(pgrep -fc '[s]mall_bites_live.py')"
echo "== 2. remote login settings (read only)"
sshd -T 2>/dev/null | grep -iE "^(passwordauthentication|permitrootlogin|pubkeyauthentication|maxauthtries|port) "
echo "keys allowed to log in as root: $(grep -cv '^\s*$\|^#' /root/.ssh/authorized_keys 2>/dev/null || echo 0)"
echo "-- successful logins, last 14 days (count, method, address)"
( journalctl -u ssh -u sshd --since "14 days ago" --no-pager 2>/dev/null; zcat -f /var/log/auth.log* 2>/dev/null ) | grep "Accepted" | awk '{for(i=1;i<=NF;i++) if($i=="from") print $(i-3), $(i+1)}' | sort | uniq -c | sort -rn | head -15
echo "-- last successful logins with dates"; last -i -F 2>/dev/null | grep -v "^reboot\|^$\|wtmp" | head -12 | cut -c1-110
echo "-- failed password attempts, last 24 hours: $( journalctl -u ssh -u sshd --since '24 hours ago' --no-pager 2>/dev/null | grep -c 'Failed password')"
echo "-- logged in right now"; who 2>/dev/null | head
echo "-- blocking of repeat attempts"; systemctl is-active fail2ban 2>&1; command -v fail2ban-client >/dev/null && fail2ban-client status sshd 2>&1 | head -8; iptables -S 2>/dev/null | grep -c -i "f2b\|DROP"; ufw status 2>/dev/null | head -3
echo '```'; } > $R 2>&1
cd /root/pe-queue && git add $R; git commit -qm "676: small bites off, login read" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
