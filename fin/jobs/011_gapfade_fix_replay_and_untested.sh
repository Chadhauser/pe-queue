#!/bin/bash
# fin 011 (own runner): (a) proof the corrected gap-fade selection works on the box: replay Friday 20 Nov with the new code path
# (no orders: selection only) and time it; (b) run the five untested ideas' own test scripts if they do not write anything.
cd /root/pe-finq/repo/fin/bots || exit 1
echo "offline test: $(timeout 300 python3 test_tick.py 2>&1 | tail -1)"
python3 - <<'PY' 2>&1 | grep -v -i warning
import time, datetime as dt, warnings; warnings.filterwarnings('ignore')
import pandas as pd, tick as T
T.H = T._creds(); uni, ed = T.universe(); day = dt.date(2026, 11, 20); t0 = time.time(); G = T.official_gaps(uni, day)
print('official opens for', len(G), 'of', len(uni), 'names in %.0fs' % (time.time() - t0)); A = T.assets(); picks = []
for s, (px, prev) in G.items():
    gap = px / prev - 1
    if abs(gap) < 0.05 or px < 3 or s in T.ETF_SYMS: continue
    tr, sh = T.can(A, s)
    if not tr or (gap > 0 and not sh): continue
    if any(abs((pd.Timestamp(x).date() - day).days) <= 1 for x in ed.get(s, [])): continue
    picks.append((s, round(gap, 3)))
picks.sort(key=lambda x: -abs(x[1])); print('20 Nov picks with the corrected rule:', len(picks), picks[:30])
for s in ('PRPO', 'JBI', 'AUNA', 'SVV'): print(' ', s, 'official open/prior close', G.get(s), '-> picked' if s in dict(picks) else '-> not picked')
PY
cd /root/pe-fin/team || exit 0
for pair in "mech_events.py E1t" "mech_events.py E1g" "mech_m7door3.py M7S" "mech_m7door3.py M7I" "mech_m7door3.py M7P"; do
  set -- $pair; echo "=== $2 ($1) writes: $(grep -c -E "to_csv|to_parquet|json.dump|open\(.*'w'|INSERT|UPDATE" $1)"
  if [ "$(grep -c -E "to_csv|to_parquet|json.dump|open\(.*'w'|INSERT|UPDATE" $1)" = "0" ]; then timeout 280 python3 $1 $2 2>&1 | grep -v -i warning | tail -6 | cut -c1-900; fi
done
