#!/bin/bash
set -o pipefail
# 499_jan_feb_262_265 (Finder 2026-11-06, interim on queue items 262, 265): jobs/499_ladder_slot.sh and jobs/499_derivative_gap.sh unchanged except the dates, Jan and Feb 2024 only, months items 260 and 263 did not read and which finished loading on 6 Nov. Rules fixed on 6 Nov, no new cuts. Read only. Both items score once n >= 300, so this is an interim read.
for job in 499_ladder_slot 499_derivative_gap; do
  SRC=/root/pe-queue/jobs/$job.sh
  echo "== JOB $job, Jan-Feb 2024"
  python3 - "$SRC" <<'PY' | bash || echo "ERROR: $job failed"
import sys
t=open(sys.argv[1]).read()
assert "market_time>='2024-03-01' AND market_time<'2026-10-01'" in t
print(t.replace("market_time>='2024-03-01' AND market_time<'2026-10-01'","market_time>='2024-01-01' AND market_time<'2024-03-01'"))
PY
done
