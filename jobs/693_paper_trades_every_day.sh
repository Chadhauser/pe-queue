#!/bin/bash
# 693 (Fri 20 Nov 2026 18:41, CEO chat order pasted by Peter): "Every passing rule places its paper trades every day, automatically.
# Fix that, and nothing else." Pauses the facts session (692) and starts a builder session that makes the paper trades appear
# through the day. The facts session is started again when this one ends. Paper only. No orders. Nothing deleted.
B=/root/pe-builder
cat > $B/BRIEF_trades.md <<'BRIEF'
You are the Builder on Peter Edwards' trading server, session 5. Started once. Do the job, leave ordinary background processes running, write your handover, stop. No idle loops; long runs go to the background with nohup + nice.
FIRST read /root/pe-queue/reports/builder_handover_3.md and /root/pe-builder/BRIEF_league.md (Peter's instruction and the HARD RULES there apply unchanged: paper only, never an order endpoint, nothing deleted, back up before editing), then /root/pe-sports/grid/ (onetest.py, league.py, cache.py, run_league.sh).
THE ORDER (CEO chat, 20 Nov 18:41): Peter asked for one thing - look at the data, then tell him the trades. 24 rules pass and the paper record shows 0 orders since 19 November. Fix that, and nothing else.
THE CAUSE AS UNDERSTOOD (confirm it or correct it in your handover, in one line): forward paper is only counted when a whole day of recording has been closed and re-run by the 6-hourly league loop, so today's trades do not exist until tomorrow, and no day after the rules passed has been run yet.
BUILD:
1. THE PAPER TRADER: a plain background program (nohup, nice, sleep loop - not an AI loop), registered in /root/pe-mechanic/watch.list, that every 10 minutes runs every way currently on paper through the SAME one test (onetest.run, same fills, same £50 limits, same 2% commission) on TODAY's recorded prices as they arrive in the live tables, and writes each paper trade once, when its entry would really have filled, to table paper_trades(way_id, day, placed_at, event, market, selection, side back/lay, price, stake, status open/closed/settled, result, profit, exit_price, exit_at). Settle from the results already recorded. A trade already written is never rewritten except to close or settle it. It must use only prices stamped before the moment it decides (no look-ahead: test this with a hand-worked check in test_known.py - a trade may not appear before its entry price existed, and replaying a finished day through the paper trader must give the same orders as the league test for that day; report the comparison for one full day).
2. THE SAME BETS ONCE: where two paper ways give the same order (same market, selection, side, minute), show it once in the trades file and count it for each way in the gate.
3. BACKFILL: run it for 19 and 20 November now so today's trades are there tonight.
4. THE FILE PETER'S CHAT READS: /root/pe-queue/reports/trades_today.md, rewritten every 10 minutes and pushed at most every 30 minutes (and once at 23:55): ONLY a table of today's paper trades - time (UK), event, selection, back or lay, price, stake, result, profit or loss - then one line: today's total, and the running total since 19 November. Nothing else in the file. Also reports/trades_YYYY-MM-DD.md kept per day.
5. THE GATE: paper_forward.md counts from paper_trades. A way that BACKS selections priced 5.0 or longer on entry (outsiders) needs 1,000 settled paper orders before the proof gate, not 100; every other way 100. Show each way's count against its own bar.
6. reports/league_top10.md, rewritten by the league loop: three things only - rules tested, rules passing, the top 10 in plain words (one line each with £ kept per £100 and orders).
Do nothing else: no new ways, no new methods, no reports beyond these.
WHEN YOU STOP: write /root/pe-queue/reports/builder_handover_5.md, plain English, under 25 lines: line 1 = why 0 paper orders were placed since 19 November, in one sentence; line 2 = the UK time today the paper trader started and how many trades it has written for 19 and 20 November; then what was checked, and anything not done. Commit and push: cd /root/pe-queue && git add reports/builder_handover_5.md reports/trades_today.md reports/trades_2026-*.md reports/league_top10.md reports/paper_forward.md 2>/dev/null; git commit -qm "builder session 5: paper trades every day" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q. Then end the session.
BRIEF
cat > $B/run_builder_trades.sh <<'SH'
#!/bin/bash
CL=$(cat /root/pe-watchman/claude_path); ts=$(date -u +%F_%H%M)
cd /root/pe-sports/grid && timeout -k 60 14400 "$CL" -p "$(cat /root/pe-builder/BRIEF_trades.md)" --allowedTools "Bash,Read,Write,Edit,Glob,Grep" --max-turns 400 --output-format text > /root/pe-builder/runs/${ts}_trades.log 2>&1
echo "builder trades session ended $(date -u '+%F %H:%M') exit $?" >> /root/pe-builder/sessions.log
/root/pe-builder/progress.sh
# the facts session (692) was paused for this one: start it again now
[ -x /root/pe-builder/run_builder_stats.sh ] && ! pgrep -f '[r]un_builder_stats' >/dev/null && nohup setsid /root/pe-builder/run_builder_stats.sh > /dev/null 2>&1 < /dev/null &
SH
chmod +x $B/run_builder_trades.sh
# pause the facts session so this one goes first (its files stay; it is restarted when this one ends)
pkill -f '[r]un_builder_stats.sh' 2>/dev/null; sleep 2; pkill -f 'BRIEF_stats.md' 2>/dev/null; sleep 3
if pgrep -f '[r]un_builder' >/dev/null; then echo "another builder session is still running - not starting"; else nohup setsid $B/run_builder_trades.sh > /dev/null 2>&1 < /dev/null & sleep 40; echo "builder session 5 (paper trades) started: $(pgrep -fc '[r]un_builder_trades.sh') at $(date -u '+%H:%M') UTC"; fi
