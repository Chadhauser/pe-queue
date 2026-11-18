#!/bin/bash
# fin 002 (own runner): Peter 18 Nov "are we smart enough to move with the bad days?" — can anything known BEFORE the ORB entry
# (overnight gap, first-5-min range vs ATR, 20-day vol, weekday, side) pick out the losing days? Re-uses job 504's test
# (filter chosen on the first half of days only, judged on the second half). Read-only on data; no orders; no sports tables written.
echo "niceness: $(nice)"
echo "--- earlier 504 output, if the shared runner kept it (read-only)"
f=$(find /root/pe-queue /root/pe-fin -maxdepth 4 -name '504*' -name '*.log' 2>/dev/null | head -1)
[ -n "$f" ] && { echo "found $f"; grep -E "trades |IS-chosen|Unfiltered OOS|READ" "$f"; }
echo "--- fresh run"
if [ -f /root/pe-fin/orb_slices.py ]; then
  cd /root/pe-fin && timeout 1500 python3 orb_slices.py 2>&1 | grep -v Warning | grep -v -E "Topstep|Apex|Monte Carlo"
else
  echo "orb_slices.py not on disk — 504 never ran here"
fi
