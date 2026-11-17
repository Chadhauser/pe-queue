#!/bin/bash
# 641 (Tue 17 Nov 2026, 08:50). Contabo emailed 08:36: unauthorised access to THEIR systems detected Sat 14 Nov (VNC passwords reset,
# internal credentials rotated). Read-only check that nobody got into OUR box: logins since 14 Nov, SSH keys, users, SSH settings,
# open ports, odd processes and cron lines, recent changes under /etc and /root/.ssh. Changes nothing. Prints no secrets.
R=/root/pe-queue/reports/security_641.md
{ echo "# Security check after Contabo's incident notice — $(date -u '+%F %H:%M') UTC"; echo
echo "## Successful logins since 14 Nov"; echo '```'
last -F -n 40 2>/dev/null | grep -vE '^(reboot|wtmp)' | head -40
journalctl -u ssh -u sshd --since '2026-11-14' 2>/dev/null | grep -E 'Accepted' | awk '{for(i=1;i<=NF;i++) if($i=="from") print $(i+1), $(i-3), $(i-2)}' | sort | uniq -c | sort -rn | head -20
echo '```'
echo "## Failed login attempts since 14 Nov (count, top sources)"; echo '```'
journalctl -u ssh -u sshd --since '2026-11-14' 2>/dev/null | grep -cE 'Failed password|Invalid user'
journalctl -u ssh -u sshd --since '2026-11-14' 2>/dev/null | grep -E 'Failed password|Invalid user' | grep -oE 'from [0-9a-f.:]+' | sort | uniq -c | sort -rn | head -8
echo '```'
echo "## SSH keys allowed for root (fingerprints, file times)"; echo '```'
for f in /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys; do [ -f "$f" ] && { echo "$f: $(wc -l < $f) keys, modified $(stat -c %y $f)"; ssh-keygen -lf "$f" 2>/dev/null | awk '{print "  ",$1,$2,$3,$4}'; }; done
echo '```'
echo "## Users with a login shell, and any extra uid 0"; echo '```'
awk -F: '$7 !~ /(nologin|false)$/ {print $1, $3, $7}' /etc/passwd; awk -F: '$3==0 {print "uid0:", $1}' /etc/passwd
echo "passwd/shadow/sudoers modified: $(stat -c '%n %y' /etc/passwd /etc/shadow /etc/sudoers 2>/dev/null | tr '\n' ';')"
echo '```'
echo "## SSH settings in force"; echo '```'; sshd -T 2>/dev/null | grep -iE '^(passwordauthentication|permitrootlogin|pubkeyauthentication|port|kbdinteractiveauthentication) '; echo '```'
echo "## Listening ports"; echo '```'; ss -tlnp 2>/dev/null | awk 'NR>1 {print $4, $6}' | sed -E 's/users:\(\("([^"]+)".*/\1/' | sort -u; echo '```'
echo "## Processes running from temp folders, and top CPU"; echo '```'
ls -l /proc/*/exe 2>/dev/null | grep -E '/tmp/|/dev/shm|/var/tmp|\(deleted\)' | awk '{print $9,$10,$11}' | head -10
ps -eo pid,user,%cpu,etime,comm --sort=-%cpu | head -8
echo '```'
echo "## Cron lines that download or decode anything"; echo '```'; crontab -l 2>/dev/null | grep -nE 'curl|wget|base64|/tmp/|/dev/shm|nc |bash -i' | grep -v '^#' | head; ls -la /etc/cron.d/ 2>/dev/null; echo '```'
echo "## Files changed since 14 Nov under /etc and /root/.ssh"; echo '```'
find /etc /root/.ssh -type f -newermt '2026-11-14' 2>/dev/null | head -40
echo '```'
} > "$R" 2>&1
cd /root/pe-queue && git add "$R" && git commit -qm "641: security check after Contabo incident notice" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
echo "641 done"
