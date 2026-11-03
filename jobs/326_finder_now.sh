#!/bin/bash
# 326: kick the Finder now for queue item 00 (goal-signal repair); exits if a run is in progress.
nohup /root/pe-finder/run.sh >/dev/null 2>&1 & echo "finder kicked $(date -u)"
