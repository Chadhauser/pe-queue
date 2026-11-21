#!/bin/bash
# 698 (Sat 21 Nov 2026 08:51, Peter: "Fix everything now", after the audit of what is running). Starts one fixer session on the
# server, separate from the builder sessions, to mend the three broken feeds and switch off what is not earning its place.
# Paper only. No orders. Nothing deleted: every switch-off is a commented timer line or a stopped process, with a backup.
F=/root/pe-fixer; mkdir -p $F/runs
crontab -l > $F/crontab_before_698.txt
cat > $F/BRIEF.md <<'BRIEF'
You are the Fixer on Peter Edwards' trading server. Started once, by Peter's order "Fix everything now" (21 Nov 2026, 08:51 UK). Work down the list in order, prove each item, write the report, stop. No idle loops. Football kicks off in volume at 12:30 and 15:00 UK today: items 1-3 come first and must be finished well before then.
NEVER: place, cancel or change an order; call any order endpoint; touch /root/REAL_MONEY_OFF (check it still exists at the start and the end and say so); delete data, tables or files; print or copy credentials (read them only through /root/pe-queue/runner/creds.py). Before changing any file copy it to <name>.bak_698; before changing the timer list it is already saved at /root/pe-fixer/crontab_before_698.txt. A switch-off = comment the timer or keepalive line with the prefix '#STOPPED-698 ' and stop the process; never remove code. Do not touch the builder sessions (/root/pe-builder, anything run_builder*), /root/pe-sports/grid/papertrader.py or run_papertrader.sh, or the mechanic. If an item cannot be done safely, leave it, and say exactly why and what is needed.
MEND (in this order):
1. The Betfair price recorder froze overnight with repeated 'catalogue 400' errors and only recovered at 07:36 UTC with a new connection; the watchman also reports KeyError('runnerName') and 'subscribed over the 200 cap'. Find the cause in the stream recorder's code and log, fix it properly (request catalogue in chunks within the limit, tolerate a missing runner name, re-authenticate and resubscribe by itself when requests start failing), restart it at a moment with the fewest live markets, and prove ticks are arriving on football, racing and tennis after the restart. Make sure it is in /root/pe-mechanic/watch.list with a staleness check (no new stream_ticks rows for 3 minutes while markets are open = restart).
2. Live match facts stopped: sofascore (expected goals, shots) about 9 Nov, espn about 15 Nov ('lo_live/espn/xg' heartbeats stale 4.7 days). Find why each stopped (crash, block, a pause marker from job 543 or later), restart what can be restarted, add each to watch.list, and prove new rows for a match being played today. If a source now blocks us, say so plainly and do not hammer it.
3. Racecards and racing results facts stopped 8-9 Nov (racing heartbeat stale 12 days). Same treatment. Prove today's cards are in.
4. The loader for Peter's free Betfair history months has loaded nothing since 16:48 UTC 20 Nov (partial months Soccer 2024-05, Soccer 2023-12, Tennis 2025-10 never complete). Find the cause, fix or skip-and-list the bad files so it moves on.
5. Results reach the paper trader only every ~6 hours (settle.py inside run_grid_recorded.sh). Give settling its own plain loop every 15 minutes (nohup, nice, in watch.list) so paper trades settle the same hour. Do not change what settle.py decides.
SWITCH OFF (not earning their place; switch-off only, as defined above):
6. The rule factory: stop run_league.sh's loop from putting NEW rules onto paper and from re-testing all 8,663 rules every 6 hours. Simplest safe way: stop that loop (comment its keepalive/watch.list line, stop the process) and leave league.py runnable by hand. The paper trader, its files and the rules already on paper carry on untouched. Check the paper trader does not depend on that loop for anything it needs today; if it does (for example the day cache), keep only that part running and say so.
7. The old sports team loop (/root/pe-sports/team/sports_team.py and its keepalive): stop it. Keep audit_nightly.py and friday_four.py timers as they are. If the hourly watchman or the scoreboard reads something only that loop writes, note it.
8. The old paper book that shows as 'bookie paper orders' on the scoreboard (paper minus £147): stop its process and keepalive. It is paper; confirm from its own code that it cannot place a real order before and after, and do not edit it.
9. The hourly watchman: change its timer from every hour to four times a day (06:15, 12:15, 18:15, 23:15 UTC).
10. Queue jobs that have re-polled for weeks: mark 240_results_pipeline_to_github and 408_liq_sample_retention_60d as closed (touch /root/pe-queue-state/done/<name>, remove the waiting marker). Leave 261, 263, 271, 272 alone: they belong to another line of work.
11. The nightly auditor still raises a false alarm that grid_history.py should be running; correct what it expects so it does not email Peter about a finished job. Also make it expect the new state after this session (items 6-9), so tonight's check does not report these switch-offs as faults.
REPORT: /root/pe-queue/reports/fix_everything_698.md, plain English, no code names where a plain name will do, one line per item 1-11: DONE / NOT DONE, what was wrong, what was changed, and the proof (a count, a time, a line from a log). First line of the file: how many of 11 are done and the UK time. Commit and push after items 1-3 and again at the end: cd /root/pe-queue && git add reports/fix_everything_698.md && git commit -qm "698: fix everything" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q. Then end the session.
BRIEF
cat > $F/run_fixer.sh <<'SH'
#!/bin/bash
CL=$(cat /root/pe-watchman/claude_path); ts=$(date -u +%F_%H%M)
cd /root && timeout -k 60 14400 "$CL" -p "$(cat /root/pe-fixer/BRIEF.md)" --allowedTools "Bash,Read,Write,Edit,Glob,Grep" --max-turns 500 --output-format text > /root/pe-fixer/runs/${ts}.log 2>&1
echo "fixer session ended $(date -u '+%F %H:%M') exit $?" >> /root/pe-fixer/sessions.log
SH
chmod +x $F/run_fixer.sh
if pgrep -f '[r]un_fixer.sh' >/dev/null; then echo "fixer already running"; else nohup setsid $F/run_fixer.sh > /dev/null 2>&1 < /dev/null & sleep 30; echo "fixer started: $(pgrep -fc '[r]un_fixer.sh') at $(date -u '+%H:%M') UTC | REAL_MONEY_OFF present: $([ -e /root/REAL_MONEY_OFF ] && echo yes || echo NO)"; fi
