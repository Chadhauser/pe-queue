#!/bin/bash
# 564 (Fri 13 Nov 2026, 16:10). The two wedges of 12-13 Nov were both the runner's `git pull` refusing: first "divergent branches"
# (a failed push left local commits), then "please commit or stash" (rebase mode + a job editing a tracked file in place).
# Fix at the root: the runner sets merge mode and auto-stash every cycle before it pulls, so neither condition can stop the queue again.
# Nothing else in runner.sh changes.
set -o pipefail
R=/root/pe-queue/runner/runner.sh; cp $R $R.bak_564
grep -q "564" $R || sed -i 's|^git pull -q 2>>/root/pe-queue-state/git.err \|\| true$|git config pull.rebase false; git config rebase.autoStash true   # 564: merge mode + autostash so a stray edit or a failed push can never wedge the pull again\ngit pull -q --no-edit 2>>/root/pe-queue-state/git.err \|\| true|' $R
bash -n $R && grep -n "564\|git pull" $R | head -4 || { cp $R.bak_564 $R; echo RESTORED; exit 1; }
cd /root/pe-queue && git config --get pull.rebase; git config --get rebase.autoStash; git status -sb | head -1
git add runner/runner.sh && git commit -q -m "564: runner pull hardening (merge mode + autostash every cycle)" && git pull -q --no-edit && git push -q && echo pushed
echo "564 done"
