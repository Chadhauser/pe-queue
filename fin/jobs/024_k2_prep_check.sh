#!/bin/bash
# fin 024 (own runner): proof on the box that the gap fade's pre-open step works: official prior closes for today, timed. No orders.
cd /root/pe-finq/repo/fin/bots || exit 1
echo "offline test: $(timeout 300 python3 test_tick.py 2>&1 | tail -1)"
python3 - <<'PY' 2>&1 | grep -v -i warning
import time, datetime as dt, tick as T
T.H = T._creds(); uni, ed = T.universe(); t0 = time.time(); day = dt.date(2026, 11, 24); pc = T.prev_closes(uni, day); print('official prior closes:', len(pc), 'of', len(uni), 'in %.0fs' % (time.time() - t0))
t0 = time.time(); pc = T.prev_closes(uni, day); print('second call (cached): %.2fs' % (time.time() - t0)); t0 = time.time(); sn = T.snapshots(uni); print('fast-feed snapshot:', len(sn), 'names in %.0fs' % (time.time() - t0))
t0 = time.time(); g = T.with_timeout(lambda: T.official_gaps(uni[:200], dt.date(2026, 11, 23)), 45, {}); print('confirm step on 200 names: %d back in %.0fs' % (len(g), time.time() - t0))
PY
