#!/bin/bash
set -o pipefail
# 499_cricket_men_thin (Finder 2026-11-07, queue item 368, Finder's own, source c): jobs/499_cricket_women_stress.sh with the two sexes swapped, so THIN and THICK are cut at the men's median of pre-off prints and women become the reference. Read only, no tables written. Same months as items 268 and 271, so an upper bound even if the numbers clear.
python3 - <<'PY' | bash
import os
s='/root/pe-queue/jobs/499_cricket_women_stress.sh'
if not os.path.exists(s): s+='.wip'
t=open(s).read()
for a,b in (("W=R[R.wm]; md=","W=R[~R.wm]; md="),("add('W '+lab,x); add('W '+lab+' OFFICIAL only',x[x.official]); add('W '+lab+' THIN',x[x.prints<thin]); add('W '+lab+' THICK',x[x.prints>=thin])","add('M '+lab,x); add('M '+lab+' THIN',x[x.prints<thin]); add('M '+lab+' THICK',x[x.prints>=thin])"),("for lab,x in R[~R.wm].groupby('lab'): add('M '+lab+' control',x)","for lab,x in R[R.wm].groupby('lab'): add('W '+lab+' reference',x)")):
    assert a in t,a
    t=t.replace(a,b)
print(t)
PY
