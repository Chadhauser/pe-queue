#!/bin/bash
set -o pipefail
# 499_flip_flow_unseen (Finder 2026-11-07, queue item 303): jobs/499_flip_flow.sh unchanged except the months, Jun to Dec 2023, which item 295 never read. May 2023 is still loading. Only item 295's FAV SELL ALL lay is scored; other lines print as context. Read only, no tables written.
J=/root/pe-queue/jobs
python3 - "$J/499_flip_flow.sh" <<'PY' | bash
import sys
t=open(sys.argv[1]).read()
a="for y,ms in ((2024,range(1,12)),(2026,range(5,12))):"
b="for y,ms in ((2023,range(6,13)),):"
assert a in t, "window text not found"
t=t.replace(a,b)
c="print(O.head(15).to_string(index=False))"
assert c in t, "print text not found"
print(t.replace(c,"print(O.to_string(index=False))"))   # print every line, so the one scored line cannot fall off the table
PY
echo "== SURVIVORS: item 303 reads FAV SELL ALL lay only, in the ITEM 295 table above"
