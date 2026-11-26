#!/bin/bash
# 720 (Thu 26 Nov 2026 18:52). The trial list (approved by Peter 22 Nov) stopped updating at 11:54 UTC today. One short fixer
# session: find why, restart it, make it unable to stall silently, fill in the missed hours. Trial only. No orders. Nothing deleted.
mkdir -p /root/pe-fixer/runs
cat > /root/pe-fixer/BRIEF_trial.md <<'BRIEF'
You are the Fixer on Peter Edwards' trading server. One job, then stop. HARD RULES: paper/trial only; never an order endpoint; nothing deleted; back up any file before editing (.bak_720); credentials only through /root/pe-queue/runner/creds.py; do not change any trial rule, the fill rules, or the paper entry rule. NOTE: do not write any wait check of the form pgrep -f run_scorecard.sh - a leftover shell (pid 393383) matches it forever.
FAULT: /root/pe-queue/reports/trial_today.md was last written and pushed at 11:54 UTC on 26 Nov ('trial list 11:42 UK'); it normally pushes every 40 minutes. The paper trader's own files are still updating. Session 24 noted the trial's cycle 'still peaks at 10.9 GB (it re-reads 22 and 23 Nov each time)' - every day adds another day to re-read, on an 18 GB server, and the watchman reports one query holding 15 GB of temp files.
DO: (1) Find the cause from the trial loop's own log and the system log (killed for memory, a crash, a hung query, a failed push) and say it in one sentence with the log line. (2) Restart it. (3) Make the cycle incremental so it cannot grow with the calendar: settled days are computed once and stored; each cycle reads only today (and yesterday until its markets settle); state the peak memory and seconds of a cycle before and after. Prove on the database that totals for 22-25 Nov are unchanged to the penny after the change (per rule). (4) Fill in the hours missed today from the recorded prices - they were recorded live, so this is still unseen data - and say how many orders were added. (5) So it can never stall silently again: a line in /root/pe-mechanic/watch.list that restarts the trial loop when trial_today.md is more than 45 minutes old, and the same staleness check for the paper trader's file and the nightly scorecard (older than 26 hours). (6) If the cause was memory, find what else is holding it (the 15 GB temp-file query: whose it is, whether it is finished work that can be stopped safely - stop it only if it belongs to a session that has ended; otherwise report it).
REPORT /root/pe-queue/reports/trial_stall_720.md, plain English, under 10 lines: cause, fix, memory and seconds before and after, totals unchanged yes/no, orders filled in, the staleness checks added, anything left. Commit and push: cd /root/pe-queue && git add reports/trial_stall_720.md reports/trial_today.md && git commit -qm "720: trial list restarted and made incremental" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q. Then end the session.
BRIEF
cat > /root/pe-fixer/run_fixer_trial.sh <<'SH'
#!/bin/bash
CL=$(cat /root/pe-watchman/claude_path); ts=$(date -u +%F_%H%M)
cd /root/pe-sports/grid && timeout -k 60 7200 "$CL" -p "$(cat /root/pe-fixer/BRIEF_trial.md)" --allowedTools "Bash,Read,Write,Edit,Glob,Grep" --max-turns 200 --output-format text > /root/pe-fixer/runs/${ts}_trial.log 2>&1
echo "fixer trial session ended $(date -u '+%F %H:%M') exit $?" >> /root/pe-fixer/sessions.log
SH
chmod +x /root/pe-fixer/run_fixer_trial.sh
nohup setsid /root/pe-fixer/run_fixer_trial.sh > /dev/null 2>&1 < /dev/null & sleep 15
echo "trial fixer: $(pgrep -fc '[r]un_fixer_trial.sh') | trial loop processes: $(pgrep -fc '[r]un_trial.sh') | free memory: $(free -g | awk '/Mem/{print $7" GB of "$2}') | $(date -u +%H:%M) UTC 26 Nov" > /root/pe-queue/reports/running_now.md
cd /root/pe-queue && git add reports/running_now.md && git commit -qm "running now" -q && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
