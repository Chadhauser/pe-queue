#!/bin/bash
# 596 (Sun 15 Nov 2026, 22:50). Tennis second pass: ten months were skipped by rate limiting (HTTP 429) in the first backfill; the script now
# retries (594). Tennis only, in the background; the engine re-runs for Tennis at the end and the Verifier re-derives.
pgrep -f results_backfill.py >/dev/null && echo "backfill still running" || { cd /root/pe-hist && nohup python3 results_backfill.py Tennis > results_backfill_tennis2.log 2>&1 & disown; sleep 60; tail -3 /root/pe-hist/results_backfill_tennis2.log | cut -c1-200; }
echo "596 done"
