#!/bin/bash
# 711 (Sat 21 Nov 2026 18:33, Peter: "Can't you backtest those trades using the new rules? Otherwise it feels like we are
# starting again"). After the slate session and any other builder session: every old paper rule and today's leads re-run on all
# recorded days under the new rules, so anything that qualifies goes straight onto paper with its history. One at a time (memory).
pgrep -f 'run_(builder[a-z_]*|goalaudit|goaltrade|books|markets)\.sh' >/dev/null && { echo "another session is running - waiting (one at a time)"; exit 75; }
B=/root/pe-builder
cat > $B/BRIEF_rebacktest.md <<'BRIEF'
You are the Builder on Peter Edwards' trading server, session 17. Read /root/pe-builder/BRIEF_league.md (HARD RULES and STANDING RULE 708), reports/paper_slate_710.md (the new entry rule - use exactly that bar), other_markets.md, goal_trade.md, offering_prices.md, steered_quoting.md if present, builder_handover_7.md. Memory: one heavy job at a time, day by day, never load more than one day of ticks at once; check free memory before each run and keep the paper trader alive.
PETER'S POINT: the slate is cleared, but the recorded data is not lost, so we are not starting again. Re-run what we already have under the NEW rules on every recorded day (31 Oct to today), now.
1. EVERY RULE THAT WAS EVER ON PAPER (the archive lists them, about 190) and TODAY'S LEADS (racing: lay under 5.0 after a 10% drift in 2 minutes before the off, and its back-side mirror on the runners that shorten; the goal trade at minutes 45-75; back the pressing side in match odds; the 13 that stayed until tonight; the football 'money waiting to back is 2-3 times the money waiting to lay' group): for each, the versions with a target, a stop (5, 10, 20% of the stake) and a time limit, backs first, no lay at 5.0 or longer.
2. THREE SLICES BY DATE, fixed before looking: A = 31 Oct-7 Nov, B = 8-14 Nov, C = 15 Nov-today. Choose the version on A only. Check on B. Confirm on C. A rule qualifies only if it is in profit after costs on B and on C, still in profit on C without its best day, and clears the raised bar for the number of versions tried on A (use the bar written in paper_slate_710.md; state it). Each rule must also carry the one-sentence reason: who is on the other side and why they keep paying. No reason, it does not qualify, however good the numbers.
3. WHAT QUALIFIES GOES ONTO PAPER TONIGHT, forward only, under the bank limits. Its history is shown separately and honestly labelled: /root/pe-queue/reports/backtest_book.md - 'BACKTEST, not paper': for each qualifying rule the sentence, the reason, and its trades on slice C only (the days it never saw when chosen) as a table like the Trades file, with the total for C and £ per day; then one line for A and one for B. Never add backtest money to the paper total.
4. IF NOTHING QUALIFIES: say so in the first line, then the five nearest, each with exactly what it failed on (B, C, best day, the bar, no reason) and by how much.
Line 1 of backtest_book.md: how many of how many qualified, and the slice-C total per day at the bank's stake for those that did. Commit and push: cd /root/pe-queue && git add reports/backtest_book.md reports/paper_forward.md reports/trades_today.md 2>/dev/null; git commit -qm "re-backtest under the new rules" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q. Then end the session.
BRIEF
cat > $B/run_builder_rebacktest.sh <<'SH'
#!/bin/bash
CL=$(cat /root/pe-watchman/claude_path); ts=$(date -u +%F_%H%M)
cd /root/pe-sports/grid && timeout -k 60 21600 "$CL" -p "$(cat /root/pe-builder/BRIEF_rebacktest.md)" --allowedTools "Bash,Read,Write,Edit,Glob,Grep" --max-turns 500 --output-format text > /root/pe-builder/runs/${ts}_rebacktest.log 2>&1
echo "builder rebacktest session ended $(date -u '+%F %H:%M') exit $?" >> /root/pe-builder/sessions.log
SH
chmod +x $B/run_builder_rebacktest.sh
nohup setsid $B/run_builder_rebacktest.sh > /dev/null 2>&1 < /dev/null & sleep 15; echo "re-backtest session started: $(pgrep -fc '[r]un_builder_rebacktest.sh')"
