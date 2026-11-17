#!/bin/bash
# 628 (Tue 17 Nov 2026, 07:00). Read only. 627: goal_alerts has no row since 7 Nov 19:04 although the monitor runs (goal_live_predictions
# is fresh) and its log shows "fired=2"; goal_events stopped 8 Nov 03:29; m1_alerts 9 Nov. Find where a fired alert is written, why
# nothing lands, and what writes goal_events. Report: reports/goal_signal_628.md
R=/root/pe-queue/reports/goal_signal_628.md
B=/root/pe-brain/repo
{
echo "# Why the goal signal sends nothing — $(date -u '+%F %H:%M') UTC"; echo
echo "## Where alerts are written"; echo '```'
grep -rnE "INSERT INTO goal_alerts|goal_alerts \(|INSERT INTO m1_alerts|INSERT INTO goal_events" $B/brain $B/*.py /root/pe-sports /root/pe-liq /root/pe-ip 2>/dev/null | grep -vE '\.bak|/jobs/' | head -20
echo '```'
F=$(grep -rlE "INSERT INTO goal_alerts" $B/brain 2>/dev/null | head -1)
echo "### $F around the insert"; echo '```'; grep -nE -B25 "INSERT INTO goal_alerts" "$F" | grep -nE "if |return|continue|send|push|telegram|kill|DRY|enabled|env|fired" | head -40; echo '```'
echo "## monitor_ht.log since 13 Nov: fired counts and errors"; echo '```'
grep -c "GOAL-SIGNAL" /root/pe-brain/monitor_ht.log
grep -E "fired=[1-9]" /root/pe-brain/monitor_ht.log | tail -8
grep -iE "error|exception|traceback|goal_alerts|insert" /root/pe-brain/monitor_ht.log | sort | uniq -c | sort -rn | head -15
echo '```'
echo "## brain environment: DB targets (host only), switches"; echo '```'
sed -E 's/(PASS(WORD)?|KEY|TOKEN|SECRET)[A-Z_]*=.*/\1=***/I; s#(://[^:]+):[^@]+@#\1:***@#' /root/pe-brain/env.sh | grep -vE '\*\*\*$' | head -20
echo '```'
echo "## what writes goal_events (stopped 8 Nov 03:29)"; echo '```'
grep -rlE "goal_events" /root/pe-*/ --include=*.py 2>/dev/null | grep -vE '\.bak|/jobs/|/repo/jobs/' | head -8
crontab -l | grep -nE "results|apifootball|api_football|goal_events|fixtures" | head
echo '```'
echo "## API-Football results pipeline (scoreboard: BROKEN since 8 Nov)"; echo '```'
grep -n "API-Football results" -A0 /root/pe-sports/team/*.py 2>/dev/null | head -3
for l in $(ls -t /root/pe-*/*results*.log /root/pe-*/*fixtures*.log 2>/dev/null | head -3); do echo "== $l"; tail -4 $l; done
echo '```'
} > "$R" 2>&1
cd /root/pe-queue && git add "$R" && git commit -qm "628: why the goal signal sends nothing" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
echo "628 done"
