#!/bin/bash
set -o pipefail
# 499_nov22_rereads (Finder 2026-11-08, 16:05 UTC run): items 451, 448 and 450 on November 2022, a month no read has used (Soccer 2022-11 DONE on the loader, 53,502 of 53,502 files, 8 Nov).
# Copy of jobs/499_dec22_rereads.sh with only the month changed (12 -> 11, December -> November labels); each job still runs unchanged except its month list and labels.
# Read only, no tables written. One month cannot reach n 300: interim reads, n stated, pooled with earlier unseen months in the report.
rewrite() {
  python3 - "$@" <<'PY'
import sys
t=open(sys.argv[1]).read()
pairs=sys.argv[2:]
assert len(pairs)%2==0
for a,b in zip(pairs[0::2],pairs[1::2]):
    assert t.count(a)>=1, "window text not found in "+sys.argv[1]+": "+a
    t=t.replace(a,b)
print(t)
PY
}
J=/root/pe-queue/jobs
echo "== ITEM 451 (jump-up FAV E1), Nov 2022 only"
rewrite $J/499_jump_up_fav_unseen.sh \
  "for y,ms in ((2023,range(1,2)),):" "for y,ms in ((2022,range(11,12)),):" \
  "January 2023 only" "November 2022 only" \
  "Jan 2023" "Nov 2022" \
  | bash || echo "ERROR: item 451 Nov 2022 failed"
echo "== ITEM 448 (N1 G2 NOT_LEVEL lay Under), Nov 2022 only"
rewrite $J/499_ht_two_up_lay.sh \
  "for y,ms in ((2023,range(1,3)),):" "for y,ms in ((2022,range(11,12)),):" \
  "Jan and Feb 2023" "Nov 2022" \
  "Jan-Feb 2023" "Nov 2022" \
  | bash || echo "ERROR: item 448 Nov 2022 failed"
echo "== ITEM 450 (level-score FAV DNB back), Nov 2022 only"
rewrite $J/499_level_fav_dnb_unseen.sh \
  "MONTHS=((2023,range(1,3)),)" "MONTHS=((2022,range(11,12)),)" \
  "ITEM 450, Jan-Feb 2023" "ITEM 450, Nov 2022" \
  | bash || echo "ERROR: item 450 Nov 2022 failed"
echo "== SURVIVORS: none can pass on one month (n under 300 by construction); interim reads only, pooled with earlier unseen months in the report"
