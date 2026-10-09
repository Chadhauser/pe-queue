#!/bin/bash
# PE job runner. Cron every 2 min. Pulls the queue repo, runs each new jobs/*.sh once, in order,
# one at a time, and files the log + status into Postgres (job_results) where Claude reads it.
exec 9>/root/pe-queue-state/runner.lock; flock -n 9 || exit 0
cd /root/pe-queue || exit 1
git pull -q 2>>/root/pe-queue-state/git.err || true
mkdir -p /root/pe-queue-state /root/pe-queue-logs
python3 /root/pe-queue/runner/report.py heartbeat >/dev/null 2>&1
for job in $(ls jobs/*.sh 2>/dev/null | sort); do
  name=$(basename "$job" .sh)
  [ -f "/root/pe-queue-state/done/$name" ] && continue
  mkdir -p /root/pe-queue-state/done
  python3 /root/pe-queue/runner/report.py start "$name"
  start=$(date +%s)
  bash "$job" > "/root/pe-queue-logs/$name.log" 2>&1; rc=$?
  echo "exit=$rc secs=$(( $(date +%s) - start ))" >> "/root/pe-queue-logs/$name.log"
  touch "/root/pe-queue-state/done/$name"
  python3 /root/pe-queue/runner/report.py finish "$name" "$rc" "/root/pe-queue-logs/$name.log"
done
