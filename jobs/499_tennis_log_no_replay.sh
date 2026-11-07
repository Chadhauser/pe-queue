#!/bin/bash
set -o pipefail
# 499_tennis_log_no_replay (Finder 2026-11-07, queue item 401, Finder's own): jobs/499_touch_log_tennis.sh and jobs/499_touch_log_tennis2.sh (items 129, 391) unchanged except that finder_tlog's replay rows are dropped: a row is kept only if total_matched is at or above 0.999 of the market's high so far, as job 497 did for ip_tape. 3.8% of pre-off rows and 18% of in-play rows fall on the last two days of bf_tennis_log. Same months, so it can only keep or kill the earlier reads.
J=/root/pe-queue/jobs
for job in 499_touch_log_tennis 499_touch_log_tennis2; do
  echo "== JOB $job, replay rows dropped"
  python3 - "$J/$job.sh" <<'PY' | bash || echo "ERROR: $job failed"
import sys
t=open(sys.argv[1]).read()
a="FROM finder_tlog"
assert t.count(a)>=1
b="FROM (SELECT * FROM (SELECT *,max(total_matched::float8) OVER (PARTITION BY market_id ORDER BY captured_at ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) hi_ FROM finder_tlog) q_ WHERE hi_ IS NULL OR total_matched IS NULL OR total_matched::float8>=hi_*0.999) finder_tlog"
print(t.replace(a,b))
PY
done
