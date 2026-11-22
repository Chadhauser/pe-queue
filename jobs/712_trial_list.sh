#!/bin/bash
# 712 (Sun 22 Nov 2026 07:42, Peter: "yes they go into the mix"). The three football rules in profit on all three date slices but
# below the raised bar go on a separate TRIAL list, scored forward from today. Not paper. Light on memory. No orders. Nothing deleted.
B=/root/pe-builder
cat > $B/BRIEF_trial.md <<'BRIEF'
You are the Builder on Peter Edwards' trading server, session 18. Short job, light on memory (football match-result markets before the start only; one day at a time; another session is running database queries). Read /root/pe-builder/BRIEF_league.md (HARD RULES, STANDING RULE 708), reports/backtest_book.md and reports/paper_slate_710.md. Do not weaken the paper entry rule and do not put anything on paper.
1. THE TRIAL LIST (new, separate from paper): table grid.trial_trades and file /root/pe-queue/reports/trial_today.md, written by a small loop of its own (plain sleep loop every 10 minutes, in /root/pe-mechanic/watch.list) using the same fill rules as the paper trader, forward only from 22 Nov 2026 00:00 UK, each rule frozen exactly as chosen on slice A in backtest_book.md - no re-choosing, no new versions:
   T1 back the favourite in football match-result markets with under £5,000 matched two minutes before the start, two minutes before the start, held to the result (BET);
   T2 football match result, an hour before the start, money waiting to back a selection is 2 times the money waiting to lay it: back it, target 40%, stop 20% of the stake, out after 30 minutes (TRADE);
   T3 football match result, ten minutes before the start, money waiting to back is 3 times the money waiting to lay: back it, held to the result (BET).
   Stake as the bank book would (2% of a £2,000 bank, £50 cap), the same bet once if two rules want it, the bank limits on. No lays in the trial. Rules that the calibration map (session 19) later reports as holding are added to this list by that session's handover, frozen the same way.
2. trial_today.md, ONLY this: first line 'TRIAL, below the bar - not paper, not proof.' Then a table like the Trades file (time UK, event, selection, back or lay, price, stake, result, profit or loss, rule). Then one line per rule: orders settled since 22 Nov, £, £ per £100, and how many more markets it needs to clear the entry bar at the current rate. Then one line: all together, today and since 22 Nov. Pushed at most every 30 minutes and at 23:55 UK. A rule that clears the entry rule's bar on these unseen days is reported at the top and promoted to paper by the existing gate; one in loss after 300 settled orders is dropped and the file says so.
3. HOUSEKEEPING, one line each, fix or say why not: the archive watermark stalled at 12 Nov; the history loader has loaded no file since 16:48 UTC 20 Nov.
WRITE /root/pe-queue/reports/trial_712.md under 10 lines: the three rules as frozen, proof of one clean cycle with today's first matches and its memory use, step 3 results. Commit and push: cd /root/pe-queue && git add reports/trial_712.md reports/trial_today.md && git commit -qm "712: trial list" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q. Then end the session.
BRIEF
cat > $B/run_builder_trial.sh <<'SH'
#!/bin/bash
CL=$(cat /root/pe-watchman/claude_path); ts=$(date -u +%F_%H%M)
cd /root/pe-sports/grid && timeout -k 60 7200 "$CL" -p "$(cat /root/pe-builder/BRIEF_trial.md)" --allowedTools "Bash,Read,Write,Edit,Glob,Grep" --max-turns 200 --output-format text > /root/pe-builder/runs/${ts}_trial.log 2>&1
echo "builder trial session ended $(date -u '+%F %H:%M') exit $?" >> /root/pe-builder/sessions.log
SH
chmod +x $B/run_builder_trial.sh
nohup setsid $B/run_builder_trial.sh > /dev/null 2>&1 < /dev/null & sleep 10; echo "trial session started: $(pgrep -fc '[r]un_builder_trial.sh')"
