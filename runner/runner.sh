#!/bin/bash
# PE job runner. Cron every 2 min. Pulls the queue repo, runs each new jobs/*.sh once, in order,
# one at a time, and files the log + status into Postgres (job_results) where Claude reads it.
exec 9>/root/pe-queue-state/runner.lock; flock -n 9 || exit 0
# children must not inherit the lock fd (a daemon started by a job would hold the queue shut)
cd /root/pe-queue || exit 1
git pull -q 2>>/root/pe-queue-state/git.err || true
mkdir -p /root/pe-queue-state /root/pe-queue-logs
python3 /root/pe-queue/runner/report.py heartbeat >/dev/null 2>&1
# progress reporter (independent of this lock) — installed once, idempotent
crontab -l 2>/dev/null | grep -q 'pe-queue/runner/progress.sh' || ( crontab -l 2>/dev/null; echo "*/5 * * * * /bin/bash /root/pe-queue/runner/progress.sh >/dev/null 2>&1" ) | crontab -
# order: never-run jobs first, then jobs that previously exited 75 (waiting/re-polling) — a 50-min re-polling download
# must not hold brand-new jobs behind it every cycle
mkdir -p /root/pe-queue-state/waiting
fresh=""; retry=""
for job in $(ls jobs/*.sh 2>/dev/null | sort); do n=$(basename "$job" .sh); if [ -f "/root/pe-queue-state/waiting/$n" ]; then retry="$retry $job"; else fresh="$fresh $job"; fi; done
for job in $fresh $retry; do
  name=$(basename "$job" .sh)
  [ -f "/root/pe-queue-state/done/$name" ] && continue
  mkdir -p /root/pe-queue-state/done
  python3 /root/pe-queue/runner/report.py start "$name"
  start=$(date +%s)
  # hard cap: no job may hold the queue for more than 3 h (248 held it 90+ min by running a recorder keepalive in the foreground)
  cap=10800; [ -f "/root/pe-queue-state/waiting/$name" ] && cap=1200   # re-polling jobs get 20 min per cycle, fresh jobs 3 h
  timeout -k 30 $cap bash "$job" 9>&- > "/root/pe-queue-logs/$name.log" 2>&1; rc=$?
  if [ "$rc" = "124" ] && [ "$cap" = "1200" ]; then echo "cycle cap 20 min reached — re-polled next cycle" >> "/root/pe-queue-logs/$name.log"; rc=75; fi
  [ "$rc" = "124" ] && echo "TIMEOUT: job killed after 3 h — start daemons with nohup ... & never in the foreground" >> "/root/pe-queue-logs/$name.log"
  echo "exit=$rc secs=$(( $(date +%s) - start ))" >> "/root/pe-queue-logs/$name.log"
  if [ "$rc" = "75" ]; then
    # 75 = WAITING on something outside the job (a token, data from another job). Not done: retried every cycle, next jobs still run.
    touch "/root/pe-queue-state/waiting/$name"
    python3 /root/pe-queue/runner/report.py finish "$name" "$rc" "/root/pe-queue-logs/$name.log"
    continue
  fi
  touch "/root/pe-queue-state/done/$name"; rm -f "/root/pe-queue-state/waiting/$name"
  python3 /root/pe-queue/runner/report.py finish "$name" "$rc" "/root/pe-queue-logs/$name.log"
done
