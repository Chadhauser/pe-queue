#!/bin/bash
set -o pipefail
# 499_jump_up_unseen_pool (Finder 2026-11-08, queue items 422, 423): jobs/499_jump_up_delay.sh unchanged except the window, Mar to May 2023 together, the three months no read of item 414 chose (Mar and Apr loaded on 8 Nov, May read 7 Nov). One read, so t and the halves are computed, not weighted by hand. Era label UNSEEN; the CHOSE audit is empty by design. Read only.
python3 - "$@" <<'PY' | bash
import sys
t=open('/root/pe-queue/jobs/499_jump_up_delay.sh').read()
for a,b in (("for y,ms in ((2023,range(5,13)),(2024,range(1,12)),(2026,range(5,11))):","for y,ms in ((2023,range(3,6)),):"),
            ("MAY23","UNSEEN"),("ITEM 422 May 2023","ITEM 422 Mar to May 2023")):
    assert a in t, a
    t=t.replace(a,b)
assert "T.dt<pd.Timestamp('2023-06-01',tz='UTC')" in t
print(t)
PY
echo "== SURVIVORS: see the UNSEEN lines above; the bar applies to UNSEEN ONE E1 and UNSEEN ONE D5"
