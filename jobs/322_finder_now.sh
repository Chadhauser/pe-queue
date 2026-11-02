#!/bin/bash
# 322: kick the Finder now (not at 02:40) so the audit of the morning's survivor (queue item 0) runs today; it exits if a run is already in progress (flock).
nohup /root/pe-finder/run.sh >/dev/null 2>&1 &
echo "finder kicked at $(date -u) — report lands in reports/finder_$(date +%F).md"
