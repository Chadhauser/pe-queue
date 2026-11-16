#!/bin/bash
# fin 001 (own runner): health of the segregated lane — FOMC calendar has the upcoming decision dates (E1 needs Dec 9 2026),
# cron lines, niceness of the tick, today's bot state, any tick errors. Read-only.
echo "niceness of this job: $(nice)"
echo "--- FOMC dates: last 5 in /root/pe-data/events/fomc.csv"; tail -5 /root/pe-data/events/fomc.csv
echo "--- FINQ cron"; crontab -l | grep '# FINQ'
echo "--- today's state"; ls -t /root/pe-finq/state/bots/day_*.json 2>/dev/null | head -1 | xargs cat 2>/dev/null | head -40
echo "--- tick errors (last 10)"; grep -E "ERROR|Traceback|-> [45][0-9][0-9]" /root/pe-finq/state/bots/bots.log 2>/dev/null | tail -10
echo "--- tick.out tail"; tail -5 /root/pe-finq/state/tick.out 2>/dev/null
df -h / | tail -1
