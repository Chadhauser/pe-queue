#!/bin/bash
# 636 (Tue 17 Nov 2026, 07:25). Read only. 635: mon=0 because get_live_fixtures keeps only MONITORED_LEAGUES. Show where that set
# comes from and what it holds now, plus af_daily.py (paused by 543) in case it feeds it. Report: reports/leagues_636.md
R=/root/pe-queue/reports/leagues_636.md; F=/root/pe-brain/repo/brain/monitor_ht.py
{ echo "# 636 — $(date -u '+%F %H:%M') UTC"; echo '```'
grep -rnE "MONITORED_LEAGUES" /root/pe-brain/repo/brain/*.py | head -12
N=$(grep -nE "^MONITORED_LEAGUES|MONITORED_LEAGUES\s*=" $F | head -1 | cut -d: -f1); [ -n "$N" ] && sed -n "$N,$((N+25))p" $F
echo "--- get_live_fixtures"; sed -n 640,668p $F
echo "--- af_daily.py head"; head -30 /root/pe-data/af_daily.py 2>&1
echo "--- live league ids the API returns right now vs the set (from the log)"; grep -E "league|LEAGUE" /root/pe-brain/monitor_ht.log | tail -5 | cut -c1-200
echo '```'; } > $R 2>&1
cd /root/pe-queue && git add $R && git commit -qm "636: monitored leagues" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
