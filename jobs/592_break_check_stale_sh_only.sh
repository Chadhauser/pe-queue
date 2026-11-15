#!/bin/bash
# 592 (Sun 15 Nov 2026, 17:15). The runner-pickup check counted every file under jobs/ on origin (.wip drafts, .py helpers) as an unrun job.
# Only *.sh files are jobs. Also drop the dead-end marker so the 16:46 false break does not suppress a real one with the same key.
set -o pipefail
S=/root/pe-sports/team/break_check.sh; cp $S $S.bak_592
python3 - <<'PY'
p='/root/pe-sports/team/break_check.sh'; s=open(p).read()
old="STALE=$(git ls-tree --name-only origin/main jobs/ 2>/dev/null | while read j;"
new="STALE=$(git ls-tree --name-only origin/main jobs/ 2>/dev/null | grep '\\.sh$' | while read j;"
assert old in s; s=s.replace(old,new,1); open(p,'w').write(s); print("stale check: .sh only")
PY
bash -n $S && echo compiles || { cp $S.bak_592 $S; echo RESTORED; exit 1; }
rm -f /root/pe-sports/team/break_sent/*-$(echo "jobs on origin older than 30 min not run and not waiting: 499_ht_state_thin.sh.wip 499_jump_up_delay_touch.sh.wip 499_late_state_census.py ;" | tr -d 0-9 | md5sum | cut -c1-8) 2>/dev/null; ls /root/pe-sports/team/break_sent/ | tail -3
echo "--- dry run:"; bash $S; echo "exit $?"; tail -1 /root/pe-queue/reports/breaks.md | cut -c1-200
echo "--- backfill progress:"; tail -4 /root/pe-hist/results_backfill.log | cut -c1-200
echo "592 done"
