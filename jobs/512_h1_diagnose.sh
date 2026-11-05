#!/bin/bash
# 512: H1 fair price v0 failed in the daemon at 09:20 with no RESULT line (the mirrored tail showed only a deprecation warning).
# Print the stored last_output, then run the script directly and capture the traceback. Diagnostic only; no state changed.
set -o pipefail
python3 - <<'PY'
import json; h=json.load(open('/root/pe-sports/team/hypotheses.json'))['hypotheses'][0]
print("status:",h.get('status')); print("last_output tail:\n", (h.get('last_output') or '')[-2000:])
PY
echo "== direct run"
cd /root/pe-sports/team && timeout 2400 python3 -I fairprice_v0.py 2>&1 | grep -v DeprecationWarning | tail -60
