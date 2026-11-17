#!/bin/bash
# 632 (Tue 17 Nov 2026, 07:05). Read only. The goal signal fired 5 times late last night (monitor_ht.log lines 854534-855515) but
# goal_advisories / goal_poisson have nothing after 15 Nov 00:19. Find the write failure. Report: reports/goal_write_632.md
R=/root/pe-queue/reports/goal_write_632.md; L=/root/pe-brain/monitor_ht.log; B=/root/pe-brain/repo/brain
{ echo "# 632 — $(date -u '+%F %H:%M') UTC"; echo '```'
grep -cE "WRITE FAIL|REAL-PRICE FAIL" $L; grep -E "WRITE FAIL|REAL-PRICE FAIL" $L | cut -c1-260 | sort | uniq -c | sort -rn | head -8
echo "--- around the last fired lines"; sed -n 855490,855530p $L | cut -c1-260
echo "--- where GOAL-SIGNAL fires and writes"; grep -rnE "GOAL-SIGNAL\]|INSERT INTO goal_advisories|INSERT INTO goal_poisson|def write_advisory" $B/*.py | head -10
echo '```'; } > $R 2>&1
cd /root/pe-queue && git add $R && git commit -qm "632: goal signal write failure" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
