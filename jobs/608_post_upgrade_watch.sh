#!/bin/bash
# 608 (Mon 16 Nov 2026, 14:55). Peter ordered the upgrade to Storage VPS 30 (1,000 GB, 18 GB, 6 cores), live migration, ticket 16240569939.
# Install a self-removing cron check (every 30 min): once the server comes back on the new plan, grow the root partition and filesystem if
# the disk got bigger but the filesystem did not, confirm every keepalive is up, and report once to reports/post_upgrade.md.
cat > /root/pe-queue-state/post_upgrade_check.sh <<'SH'
#!/bin/bash
MEM=$(free -g | awk '/Mem:/{print $2}'); DISK=$(lsblk -bdno SIZE /dev/sda); FS=$(df -B1 --output=size / | tail -1)
[ "$MEM" -lt 14 ] && [ "$DISK" -lt 400000000000 ] && exit 0      # still on the old plan
R=/root/pe-queue/reports/post_upgrade.md
{ echo "# After the upgrade $(date -u '+%F %H:%M') UTC"; echo '```'; echo "memory ${MEM} GB, disk device $((DISK/1000000000)) GB, filesystem $((FS/1000000000)) GB"
  if [ $((DISK - FS)) -gt 50000000000 ]; then
    command -v growpart >/dev/null || apt-get install -y -q cloud-guest-utils >/dev/null 2>&1
    P=$(findmnt -no SOURCE /); N=$(echo $P | grep -o '[0-9]*$'); growpart /dev/sda $N && resize2fs $P && echo "filesystem grown"
  fi
  df -h / | tail -1; uptime -s
  for p in stream_client ip_tape liq_sample xx_tape bookie_v2 monitor_ht sports_team; do echo "$p: $(pgrep -fc $p)"; done
  echo '```'; } > $R 2>&1
crontab -l | grep -v post_upgrade_check | crontab -
cd /root/pe-queue && git add reports/post_upgrade.md && git commit -qm "post-upgrade check" && git pull -q --no-rebase --no-edit && git push -q
SH
chmod +x /root/pe-queue-state/post_upgrade_check.sh && bash -n /root/pe-queue-state/post_upgrade_check.sh && ( crontab -l | grep -v post_upgrade_check; echo "*/30 * * * * /root/pe-queue-state/post_upgrade_check.sh" ) | crontab - && crontab -l | grep post_upgrade
echo "608 done"
