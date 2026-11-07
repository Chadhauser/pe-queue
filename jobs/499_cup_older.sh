#!/bin/bash
set -o pipefail
# 499_cup_older (Finder 2026-11-07, queue item 292): jobs/499_cup_ties.sh and jobs/499_cup_minnow.sh unchanged except the months, Jun to Dec 2023, which neither read. Interim read: the item pools the two lines and scores once n >= 300. Read only.
rewrite() {
  python3 - "$1" "$2" "$3" <<'PY'
import sys
t=open(sys.argv[1]).read()
a,b=sys.argv[2],sys.argv[3]
assert a in t, "window text not found in "+sys.argv[1]
print(t.replace(a,b))
PY
}
J=/root/pe-queue/jobs
echo "== JOB 499_cup_ties, Jun to Dec 2023"
rewrite $J/499_cup_ties.sh "for lo,hi in (('2024-01-01','2024-04-01'),('2024-04-01','2024-07-01'),('2024-07-01','2024-10-01'),('2024-10-01','2024-12-01'),('2026-05-01','2026-08-01'),('2026-08-01','2026-09-01'),('2026-09-01','2026-11-01')):" "for lo,hi in (('2023-06-01','2023-09-01'),('2023-09-01','2024-01-01')):" | bash || echo "ERROR: cup_ties failed"
echo "== JOB 499_cup_minnow, Sep to Dec 2023"
rewrite $J/499_cup_minnow.sh "for lo,hi in (('2024-01-01','2024-04-01'),('2024-04-01','2024-06-01'),('2024-09-01','2024-12-01'),('2026-05-01','2026-06-01'),('2026-09-01','2026-11-01')):" "for lo,hi in (('2023-09-01','2024-01-01'),):" | bash || echo "ERROR: cup_minnow failed"
echo "== SURVIVORS: item 292 reads DIVS and KNOWN_AWAY KNOWN back only, interim until n >= 300"
