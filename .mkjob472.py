src=open('.diag472e.py').read()
hdr='''#!/bin/bash
set -o pipefail
# 499_btts_bound_diag (Finder 2026-11-09, 01:45 UTC run, lane default/top, queue item 472's trade-level check; the code is .diag472c.py from 8 Nov,
# cut to Oct 2022-Dec 2023 so it fits the run (57 of the 87 GAP2 trades); the rule is unchanged from jobs/499_btts_bound.sh).
# Question: are the GAP2 wins prints matched as the market closes at a goal? Per trade it reads whether OU1.5 and BTTS Yes print again after entry.
# Run 9 Nov: 40 of 57 GAP2 trades were the last print on both markets (closed at entry), won 0.950 v 0.558 implied: an artefact, and not fillable.
# Usage: bash jobs/499_btts_bound_diag.sh   (about 10 min on the local DB)
cd /root/pe-queue && python3 - "$@" <<'PY'
'''
open('jobs/499_btts_bound_diag.sh','w').write(hdr+src.rstrip('\n')+'\nPY\n')
print('ok')
