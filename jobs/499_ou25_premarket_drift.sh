#!/bin/bash
set -o pipefail
# 499_ou25_premarket_drift (Finder 2026-11-08, queue item 458, Finder's own, source c/d, breadth door of item 456).
# jobs/499_mo_premarket_drift.sh unchanged except the market type, the role labels (OVER, UNDER) and the printed labels: each text replaced must exist (assert), nothing else moves.
# Rule fixed in the claim commit before any OU2.5 price was read. Read only, no tables written.
rewrite() {
  python3 - "$@" <<'PY'
import sys
t=open(sys.argv[1]).read()
pairs=sys.argv[2:]
assert len(pairs)%2==0
for a,b in zip(pairs[0::2],pairs[1::2]):
    assert t.count(a)>=1, "text not found in "+sys.argv[1]+": "+a
    t=t.replace(a,b)
print(t)
PY
}
J=/root/pe-queue/jobs
echo "== JOB 499_mo_premarket_drift on OVER_UNDER_25, item 458"
rewrite $J/499_mo_premarket_drift.sh \
  "market_type='MATCH_ODDS'" "market_type='OVER_UNDER_25'" \
  "load_results(con,['MATCH_ODDS'])" "load_results(con,['OVER_UNDER_25'])" \
  "official MO markets" "official OU2.5 markets" \
  "    if sel=='The Draw': return 'DRAW'" "    if sel.startswith('Over'): return 'OVER'
    if sel.startswith('Under'): return 'UNDER'
    if sel=='The Draw': return 'DRAW'" \
  "for rl in ('HOME','AWAY','DRAW'):" "for rl in ('OVER','UNDER'):" \
  "== ITEM 456, thirty scored lines" "== ITEM 458 (OU2.5), thirty scored lines" \
  | bash -s -- "$@" || echo "ERROR: item 458 failed"
