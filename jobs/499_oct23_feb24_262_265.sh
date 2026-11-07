#!/bin/bash
set -o pipefail
# 499_oct23_feb24_262_265 (Finder 2026-11-07, queue items 262, 265): jobs/499_ladder_slot.sh and jobs/499_derivative_gap.sh unchanged except the dates, Oct 2023 to Feb 2024 as ONE window, so the pooled n, t and halves come from the engine rather than by hand. Oct 2023 reads DONE on the loader as of 7 Nov (64,583 files). Sep 2023 is still loading, so it is left out. Rules fixed on 6 Nov, no new cuts. Read only.
for job in 499_ladder_slot 499_derivative_gap; do
  SRC=/root/pe-queue/jobs/$job.sh
  echo "== JOB $job, Oct 2023 to Feb 2024"
  python3 - "$SRC" <<'PY' | bash || echo "ERROR: $job failed"
import sys
t=open(sys.argv[1]).read()
assert "market_time>='2024-03-01' AND market_time<'2026-10-01'" in t
print(t.replace("market_time>='2024-03-01' AND market_time<'2026-10-01'","market_time>='2023-10-01' AND market_time<'2024-03-01'"))
PY
done
