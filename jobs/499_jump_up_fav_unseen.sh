#!/bin/bash
set -o pipefail
# 499_jump_up_fav_unseen (Finder 2026-11-08, queue item 451, Finder's own, source a, from items 414 and 422): item 414's jump-up signal, favourite leg only, on January 2023, a month no read has used (Soccer 2023-01 read DONE on the loader, 52,686 of 52,686 files, 8 Nov).
# jobs/499_jump_up_delay.sh unchanged except the month list and labels, the same rewrite pattern as jobs/499_feb23_rereads.sh: each text replaced must exist (assert), nothing else moves.
# Scored line: UNSEEN FAV E1 (worse of the first in-play print and the next within 120 s, one tick adverse, GBP 10, 2%, official result, one bet a game). Read only, no tables written.
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
echo "== JOB 499_jump_up_delay, January 2023 only, item 451 (UNSEEN FAV E1 scored; ONE, OUT, DRAW and the delayed lines for reading)"
rewrite $J/499_jump_up_delay.sh \
  "for y,ms in ((2023,range(5,13)),(2024,range(1,12)),(2026,range(5,11))):" "for y,ms in ((2023,range(1,2)),):" \
  "MAY23" "UNSEEN" \
  "ITEM 422 May 2023" "ITEM 451 Jan 2023" \
  | bash || echo "ERROR: jump_up_delay Jan 2023 failed"
echo "== SURVIVORS: the bar applies to UNSEEN FAV E1 (Jan 2023 only); one month cannot reach n 300, so this is an interim read, n stated"
