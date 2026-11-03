#!/bin/bash
# 336: Finder goes to FOUR lanes for the 4 Nov belt-and-braces run. A/B as before; C and D run at :00 and :40 of the
# alternate hours and take from the bottom of the queue like B. flock is per lane (run.sh already keys the lock on FINDER_LANE).
# Postgres is capped at 4 GB from tonight: each lane must SET work_mem='64MB' and statement_timeout='2400s' in its SQL (brief says so).
grep -q "FOUR LANES" /root/pe-queue/watchman/FINDER.md || cat >> /root/pe-queue/watchman/FINDER.md <<'MD'

## FOUR LANES (from 4 Nov 2026)
Lanes A and B take from the TOP of the TODO list, C and D from the BOTTOM. Before claiming an item, re-read the queue file and skip anything already RUNNING. Postgres is capped at 4 GB RAM: open every connection with `SET work_mem='64MB'; SET statement_timeout='2400s';`, pull data in chunks (by season or by month), never `SELECT *` from bf_hist_price or liq_sample without a market/minute filter. One job per item, <= 2.5 h. If a job is killed by the cap, split the item in two and mark the first half DONE with its partial result rather than re-running the whole thing.
MD
( crontab -l 2>/dev/null | grep -v pe-finder/run.sh
  echo "40 2,8,14,20 * * * /root/pe-finder/run.sh"
  echo "20 3,9,15,21 * * * FINDER_LANE=B /root/pe-finder/run.sh"
  echo "0 5,11,17,23 * * * FINDER_LANE=C /root/pe-finder/run.sh"
  echo "40 5,11,17,23 * * * FINDER_LANE=D /root/pe-finder/run.sh" ) | crontab -
echo "finder cron:"; crontab -l | grep pe-finder
echo "lock keyed per lane?"; grep -n "lock" /root/pe-finder/run.sh | head -3
