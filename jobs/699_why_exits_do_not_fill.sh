#!/bin/bash
# 699 (Sat 21 Nov 2026 11:18, Peter: "The non filling of trades is fairly worrying"). One short builder session, after any running
# one: say exactly why half the paper trade exits did not fill, by cause, and what exit would have filled. Read and report only,
# plus exit variants as rows. Paper only. No orders. Nothing deleted.
B=/root/pe-builder
cat > $B/BRIEF_exits.md <<'BRIEF'
You are the Builder on Peter Edwards' trading server, session 8. Started once. Short job: answer one question with numbers, write one page, stop. Read /root/pe-queue/reports/builder_handover_6.md and /root/pe-builder/BRIEF_league.md first (HARD RULES unchanged: paper only, never an order endpoint, nothing deleted, back up before editing). Do not disturb a running winners session's files.
THE QUESTION (Peter): half of the paper trades' exits did not fill (50% of 6,218; 1,412 only in part; missed exits cost £7,621). Why, and is it the market or the way our rules ask to get out?
FIND, for every paper TRADE since 19 November whose exit was missed or part-filled, the cause, from the recorded prices at the moment the exit was due: (a) no price on offer at all on the exit side; (b) a price but less than £2 / less money than the position needed; (c) the quote was stale or delayed so the test refused it; (d) the market was suspended or already closed at the exit moment (racing in running is over in minutes - check exits timed as 'thirds of play'); (e) a rested closing order that was never traded through; (f) the exit moment never arrived (no in-play, abandoned, no result); (g) anything else. Give counts and £ by cause, split by sport, by before-the-start against in-play exits, and by entry price band (under 2, 2-5, 5-10, 10+).
THEN, for the same trades: what would have happened with an exit that takes whatever price is on offer (i) at the due moment or the first fresh quote within 60 seconds after it, (ii) with a stop at 10% of the stake and a target at 10%, checked every tick from entry, filled at the real price on offer when hit. How many would then have got out, at what cost per £100 against the paper result. Also: at entry time, how much money was on offer on the EXIT side, and does a rule 'only enter when at least twice the stake is on offer on the way out' separate the trades that got out from those that did not.
ALSO one line each: is the test too strict anywhere (refusing fills that a real order would have got) or too generous (giving fills that would not have happened); and the fill rate of exits in football alone, racing alone, tennis alone.
WRITE /root/pe-queue/reports/exits_why.md: plain English, one screen, the answer in the first three lines (the biggest cause, its share, and the one change that fixes most of it), then the tables. Commit and push: cd /root/pe-queue && git add reports/exits_why.md && git commit -qm "why exits do not fill" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q. Then end the session.
BRIEF
cat > $B/run_builder_exits.sh <<'SH'
#!/bin/bash
CL=$(cat /root/pe-watchman/claude_path); ts=$(date -u +%F_%H%M)
cd /root/pe-sports/grid && timeout -k 60 7200 "$CL" -p "$(cat /root/pe-builder/BRIEF_exits.md)" --allowedTools "Bash,Read,Write,Edit,Glob,Grep" --max-turns 200 --output-format text > /root/pe-builder/runs/${ts}_exits.log 2>&1
echo "builder exits session ended $(date -u '+%F %H:%M') exit $?" >> /root/pe-builder/sessions.log
SH
chmod +x $B/run_builder_exits.sh
# status line for the chat: what is running right now
echo "running now: builder $(pgrep -fa '[r]un_builder' | awk '{print $NF}' | tr '\n' ' ') | fixer $(pgrep -fc '[r]un_fixer.sh') | papertrader $(pgrep -fc '[r]un_papertrader')" > /root/pe-queue/reports/running_now.md
cd /root/pe-queue && git add reports/running_now.md && git commit -qm "running now" -q && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
nohup setsid $B/run_builder_exits.sh > /dev/null 2>&1 < /dev/null &
sleep 20; echo "exits session started: $(pgrep -fc '[r]un_builder_exits.sh')"
