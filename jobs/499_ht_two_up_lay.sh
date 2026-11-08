#!/bin/bash
set -o pipefail
# 499_ht_two_up_lay (Finder 2026-11-08, queue item 448, Finder's own, source c thin books, from item 447): item 447's line N1 G2 NOT_LEVEL lay Under (2-0 or 0-2 at the break, lay Under 2.5 55-62 min after the first in-play print, no second-half goal before entry), on months before Mar 2023 (Jan and Feb 2023, both read DONE on the loader 8 Nov), UNSEEN games only.
# jobs/499_ht_state_thin.sh unchanged except the month list and the scored line, the rewrite pattern of jobs/499_feb23_rereads.sh: each text replaced must exist (assert), nothing else moves. Read only, no tables written.
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
echo "== JOB 499_ht_state_thin, Jan and Feb 2023, item 448 (scored: N1 G2 NOT_LEVEL lay U, UNSEEN games)"
rewrite $J/499_ht_state_thin.sh \
  "for y,ms in ((2023,range(3,13)),(2024,range(1,11)),(2026,range(4,11))):" "for y,ms in ((2023,range(1,3)),):" \
  "== ITEM 447 (UNSEEN games)" "== ITEM 448 Jan-Feb 2023 (UNSEEN games), for reading" \
  "P_=O[O.PASS==True]" "print('\n== ITEM 448 scored line, Jan-Feb 2023 UNSEEN'); print(row('N1 G2 lay U NOT_LEVEL *',T[(T.N==1)&(T.G==2)&(~T.lev)],'vl')); P_=O[(O.line=='N1 G2 lay U NOT_LEVEL')&(O.PASS==True)]" \
  | bash || echo "ERROR: ht_state_thin Jan-Feb 2023 failed"
echo "== SURVIVORS: the bar applies to N1 G2 NOT_LEVEL lay U only; about 9 trades a month, so this is an interim read, n stated"
