#!/bin/bash
# 660 (Thu 19 Nov 2026, 07:05). 659 found book_recorder, small_bites_live, coherence_paper, v3_recorder and monitor_ht NOT running since
# ~09:35 UTC 18 Nov although their keepalive crons exist; only bookie_v2 and stream_client are up (both restarted ~10:20 UTC 18 Nov).
# Find why (reboot / OOM / disk / script error), then start each one by its own keepalive script and show it stays up.
R=/root/pe-queue/reports/recorders_660.md
T=/root/pe-sports/team
{ echo "# 660 — $(date -u '+%F %H:%M') UTC"; echo '```'
echo "== uptime / last boot"; uptime; who -b
echo "== disk"; df -h / /root 2>/dev/null | uniq
echo "== memory"; free -m
echo "== OOM / kills since 18 Nov"; journalctl -k --since '2026-11-18 08:00' 2>/dev/null | grep -iE 'oom|killed process' | tail -15 | cut -c1-200
dmesg -T 2>/dev/null | grep -iE 'oom|killed process' | tail -10 | cut -c1-200
echo "== cron running?"; pgrep -a cron | head -3; journalctl -u cron --since '2026-11-19 06:30' 2>/dev/null | tail -5 | cut -c1-200
for s in run_book_recorder.sh run_small_bites_live.sh run_coherence_paper.sh run_v3_recorder.sh; do
  echo "== $s"; cat $T/$s | cut -c1-200
done
echo "== run_monitor_ht.sh"; cat /root/pe-brain/run_monitor_ht.sh | cut -c1-200
echo "== log tails"
for l in small_bites_live coherence_paper v3_recorder; do echo "-- $l"; ls -la $T/$l*.log 2>/dev/null | head -2; tail -6 $(ls -t $T/$l*.log 2>/dev/null | head -1) 2>/dev/null | cut -c1-220; done
echo "-- monitor_ht"; ls -t /root/pe-brain/*.log /root/pe-brain/repo/*.log 2>/dev/null | head -3; tail -6 $(ls -t /root/pe-brain/*monitor*.log /root/pe-brain/repo/*monitor*.log 2>/dev/null | head -1) 2>/dev/null | cut -c1-220
echo "== start each now (same as its keepalive)"
for s in $T/run_book_recorder.sh $T/run_small_bites_live.sh $T/run_coherence_paper.sh $T/run_v3_recorder.sh /root/pe-brain/run_monitor_ht.sh; do
  PGAPPNAME= nohup setsid $s >/dev/null 2>&1 < /dev/null &
done
sleep 60
echo "== after 60 s"; ps -eo pid,etime,rss,cmd | grep -E 'book_recorder|small_bites_live|coherence_paper|v3_recorder|monitor_ht' | grep -v grep | cut -c1-160
for l in book_recorder small_bites_live coherence_paper v3_recorder; do echo "-- $l"; tail -4 $(ls -t $T/$l*.log 2>/dev/null | head -1) 2>/dev/null | cut -c1-220; done
echo '```'; } > $R 2>&1
cd /root/pe-queue && git add $R && git commit -qm "660: recorders down" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
