#!/bin/bash
set -o pipefail
# 499_dec23_262_265 (Finder 2026-11-07, interim on queue items 262, 265): jobs/499_ladder_slot.sh and jobs/499_derivative_gap.sh unchanged except the dates, Dec 2023 only, a month items 260 and 263 did not read and which the loader holds at 47,622 of 47,631 files. Rules fixed on 6 Nov, no new cuts. Read only. Both items score once n >= 300, so this is an interim read, pooled by hand with Jan-Feb 2024 from jobs/499_jan_feb_262_265.sh.
for job in 499_ladder_slot 499_derivative_gap; do
  SRC=/root/pe-queue/jobs/$job.sh
  echo "== JOB $job, Dec 2023"
  python3 - "$SRC" <<'PY' | bash || echo "ERROR: $job failed"
import sys
t=open(sys.argv[1]).read()
assert "market_time>='2024-03-01' AND market_time<'2026-10-01'" in t
print(t.replace("market_time>='2024-03-01' AND market_time<'2026-10-01'","market_time>='2023-12-01' AND market_time<'2024-01-01'"))
PY
done
