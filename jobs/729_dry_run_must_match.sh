#!/bin/bash
# 729 (Sat 28 Nov 2026 05:15): Peter's order of 27 Nov said of the dry run "They must match". At 05:10 it is 50 of 58: six differ
# because the dry runner decides 5 seconds before the trial does, two were never looked at (a fault in the new schedule). Also
# the book recorder has failed every 30 s since 27 Nov 05:47 UTC ("cursor already closed"). Fix all three. Places nothing.
B=/root/pe-builder
cat > $B/BRIEF_dry_match.md <<'EOF'
You are a Builder on Peter Edwards' trading server: a short repair. Read /root/pe-builder/BRIEF_league.md, then /root/pe-builder/BRIEF_safe_path.md - its ABSOLUTE LIMITS A to E bind you exactly (no order, cancel, replace or update call to any exchange, ever; do not touch /root/REAL_MONEY_OFF; no ON file; nothing deleted, archive copy before any edit; no secrets written anywhere; do not edit /root/pe-sports/grid). Then read /root/pe-queue/reports/safe_path_727.md and dry_run_t1.md.
Peter's order says of the dry run against T1: "They must match." It is 50 of 58. Fix, in this order:
1. THE BOOK RECORDER has failed every 30 s since 27 Nov 05:47 UTC with "cursor already closed". That is lost data for everything, not only this job. Find the cause, fix it (archive copy first, restart it cleanly at a quiet moment, do not disturb the other recorders), show it writing rows again, and say exactly what was lost between which times and whether the trial's T1 numbers for 27-28 Nov can still be trusted.
2. THE TWO NEVER LOOKED AT (markets 1.266078510 and 1.265836230, 27 Nov 23:58 UK): find why the dry runner's schedule missed them, fix it, add a test that would have caught it, and replay 27-28 Nov to show every trial market is now seen.
3. THE FIVE SECONDS: the dry runner decides at the start minus 125 s and the trial at minus 120 s, so a quote in between changes the pick. A real order must be the same pick as its paper twin, so make the dry runner decide on exactly the quote the trial uses (the trial's moment and its rule for how old a quote may be), without editing the trial. Replay 27-28 Nov: the target is every order paired; list any that still differ with the cause.
4. Restart the dry runner cleanly, write the new start time to /root/pe-real/dry_started (keep the old one in dry_started.history): the 2 days run again from this fix. Re-run the whole test file and the one-file search and paste their last lines.
5. In safe_path_727.md add a dated section at the top (under line 1, which stays the no-real-order line): what was wrong, what was fixed, the replay count, the new end time. Also there, two things for Peter, plainly: (a) which program placed the 269 real bets of 15 Oct to 8 Nov (-£13.20) - look harder: cron history, logs, process accounting, order references and strategy references on Betfair's own records (read-only), file times; name it or say what evidence is missing; confirm it is among the locked files or lock it; (b) the daily loss limit counted every open £2 order as a loss and stopped the placer for the day at the 10th open order: say in one line what "count only settled losses plus this order" would have done on the same day, as an option for Peter - do not change the limit.
Commit and push: cd /root/pe-queue && git add reports/safe_path_727.md reports/dry_run_t1.md && git commit -qm "dry run must match: recorder fixed, schedule fixed, same moment as the trial; 2 days restart" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q. Then end the session.
EOF
cat > $B/run_dry_match.sh <<'SH'
#!/bin/bash
CL=$(cat /root/pe-watchman/claude_path); ts=$(date -u +%F_%H%M)
cd /root/pe-real && timeout -k 60 14400 "$CL" -p "$(cat /root/pe-builder/BRIEF_dry_match.md)" --allowedTools "Bash,Read,Write,Edit,Glob,Grep" --max-turns 400 --output-format text > /root/pe-builder/runs/${ts}_dry_match.log 2>&1
echo "dry match session ended $(date -u '+%F %H:%M') exit $?" >> /root/pe-builder/sessions.log
date +%s > /root/pe-real/build_session_ended
SH
chmod +x $B/run_dry_match.sh
nohup setsid $B/run_dry_match.sh > /dev/null 2>&1 < /dev/null &
sleep 10
echo "729 started $(date -u +%H:%M) UTC 28 Nov: dry run must match (recorder, schedule, same moment as the trial). Running: $(pgrep -fc '^/bin/bash /root/pe-builder/run_dry_match.sh') | REAL_MONEY_OFF present: $([ -e /root/REAL_MONEY_OFF ] && echo yes || echo NO) | ON file: $([ -e /root/pe-real/REAL_MONEY_ON ] && echo YES || echo no) | free memory $(free -g | awk '/Mem/{print $7}') GB" >> /root/pe-queue/reports/running_now.md
cd /root/pe-queue && git add reports/running_now.md && git commit -qm "running now: 729" -q && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
