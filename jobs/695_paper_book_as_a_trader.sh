#!/bin/bash
# 695 (Sat 21 Nov 2026 08:43, Peter: "are you blindly backing or laying and just waiting for a win? This is not trading").
# Builder session 6: split the paper record into TRADES (in and out, closed before the result) and BETS (held to the result),
# and run a second paper book the way a real bank would be run. Paper only. No orders. Nothing deleted.
B=/root/pe-builder
cat > $B/BRIEF_book.md <<'BRIEF'
You are the Builder on Peter Edwards' trading server, session 6. Started once. Do the job, leave ordinary background processes running, write your handover, stop. No idle loops.
FIRST read /root/pe-queue/reports/builder_handover_5.md and /root/pe-builder/BRIEF_league.md (Peter's instruction and the HARD RULES apply unchanged: paper only, never an order endpoint, nothing deleted, back up before editing), then /root/pe-sports/grid/papertrader.py.
WHY: the paper record shows minus £7,137 in two days on about 5,400 bets. Peter's reading: this is blind backing and laying and waiting for a result, not trading. He is right that nothing separates the two and nothing limits the book. Fix exactly that. No new ways, no new methods.
1. LABEL every way and every paper trade as TRADE (the rule itself closes the position before the result: an exit at a later moment or a rested closing order) or BET (held to the result). A TRADE whose exit could not fill and was held is still a TRADE, marked 'exit missed'.
2. ANALYSIS, written to /root/pe-queue/reports/paper_breakdown.md, plain English, one screen: for 19, 20 and 21 November so far, counted once per bet - money staked, profit or loss and £ per £100 staked, for TRADES and for BETS separately; then the same by sport; then the ten rules that lost most and the ten that made most, one line each (plain sentence, TRADE or BET, orders, £ staked, profit or loss, what the league test said per £100). Then one line: how much of the total loss comes from BETS, how much from outsiders (entry price 5.0 or longer), how much from trades whose exit was missed. Then: for the TRADES, what share of exits filled, and the average minutes a position was open.
3. THE BANK BOOK: a second paper book, table grid.paper_bank, run by the same paper trader from the same trades, as a real £2,000 bank would be: TRADES only (no BETS); the same bet taken once however many rules want it; stake 2% of the bank a trade (£50 cap), lay liability the same; no more than 20% of the bank at risk at one moment and 5% on one event (a trade that would break a limit is skipped and counted as skipped); a rule that has lost 3% of the bank in a day stops for that day; the whole book stops for the day at minus 6%. Backfill it for 19-21 November. This is a view of what a disciplined bank would have done with the same rules - the full paper record and the proof gate counts stay exactly as they are.
4. trades_today.md: unchanged table, but add a first column Kind (trade or bet) and, under the existing total line, ONE more line: 'Bank book (£2,000, trades only, limits on): today £x, since 19 November £y, bank now £z, skipped n.' Nothing else added.
CHECKS: hand-worked checks in test_known.py for the label, each limit and the daily stops; replay 19 November twice and get the same bank book.
WHEN YOU STOP: write /root/pe-queue/reports/builder_handover_6.md under 20 lines: line 1 = the split of the loss between TRADES and BETS in £; line 2 = the bank book result for 19, 20, 21 November; then what was checked and anything not done. Commit and push: cd /root/pe-queue && git add reports/builder_handover_6.md reports/paper_breakdown.md reports/trades_today.md 2>/dev/null; git commit -qm "builder session 6: trades against bets, bank book" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q. Then end the session.
BRIEF
cat > $B/run_builder_book.sh <<'SH'
#!/bin/bash
CL=$(cat /root/pe-watchman/claude_path); ts=$(date -u +%F_%H%M)
cd /root/pe-sports/grid && timeout -k 60 14400 "$CL" -p "$(cat /root/pe-builder/BRIEF_book.md)" --allowedTools "Bash,Read,Write,Edit,Glob,Grep" --max-turns 400 --output-format text > /root/pe-builder/runs/${ts}_book.log 2>&1
echo "builder book session ended $(date -u '+%F %H:%M') exit $?" >> /root/pe-builder/sessions.log
SH
chmod +x $B/run_builder_book.sh
if pgrep -f '[r]un_builder' >/dev/null; then echo "a builder session is still running - not starting a second one"; exit 75; else nohup setsid $B/run_builder_book.sh > /dev/null 2>&1 < /dev/null & sleep 40; echo "builder session 6 started: $(pgrep -fc '[r]un_builder_book.sh')"; fi
