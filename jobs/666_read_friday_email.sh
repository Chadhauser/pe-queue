#!/bin/bash
# 666 (Thu 19 Nov 2026, 08:20). Read only: friday_email.py from line 40 and its .sh, so the proof-gate table can go into Friday's email.
R=/root/pe-queue/reports/friday_666.md
{ echo '```'; sed -n '40,200p' /root/pe-sports/team/friday_email.py | cut -c1-240; echo ----; cat /root/pe-sports/team/friday_email.sh; echo '```'; } > $R 2>&1
cd /root/pe-queue && git add $R && git commit -qm "666: read friday email" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
