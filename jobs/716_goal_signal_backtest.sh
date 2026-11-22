#!/bin/bash
# 716 (Sun 22 Nov 2026 17:50, Peter: "Can you back test that?"). After the scorecard session: the same accuracy scorecard run
# back over every match we can replay honestly - all recorded days, then years of history with the inputs that exist there.
# No trading, no paper. Nothing deleted.
pgrep -f '[r]un_scorecard.sh' >/dev/null && { echo "scorecard session still running - waiting"; exit 75; }
cat > /root/pe-builder/BRIEF_scoreback.md <<'BRIEF'
You are a Builder on Peter Edwards' trading server, session 23. Light on memory (one day or one month at a time; database-side where possible; other sessions are running). Work in /root/pe-sports/goaltrade (new files). Read /root/pe-builder/BRIEF_league.md (HARD RULES), reports/goal_signal_scorecard.md and reports/goal_signal_audit.md. Reuse the scorecard code exactly, so the backtest and the nightly scorecard are the same measurement. No trading, no paper.
PETER'S QUESTION: can the accuracy check be backtested. Yes - do it, at two depths, and keep them apart:
A. EVERY RECORDED DAY (31 Oct to today), version 2 with all its inputs, replayed minute by minute using only what was known at each minute with each feed's delay. Version 2 was FITTED on some of these days: say exactly which days it was fitted on and report those separately from the days it never saw; only the unseen days count as accuracy. Goal times: the score feed where we have it; for matches without one, goals read from the Betfair market's own suspensions and price jumps (say how reliable that is against matches where both exist). Output the same scorecard as the nightly one: HIGH / NORMAL / LOW hit rates against the normal rate for the minute and score, share of goals caught, minutes of warning, HIGH calls with no goal - per day (one line each) and in total, with the range it could plausibly be.
B. YEARS OF HISTORY (football, Jan 2019 onward, the history files): only the inputs that exist there (the over/under and match prices minute by minute and how they move against normal time decay; no money-per-minute, no live stats). Fit a price-only version on the oldest third, check on the middle third, report accuracy on the newest third, which it never saw. Goals from the price jumps and results (validate the method on recorded days where the true goal times are known, and give its error). Same scorecard, per season. Say plainly how much weaker the price-only version is than the full version on the recorded days, so the long history is read correctly.
THEN ONE PLAIN PARAGRAPH: over how many matches and how long has the signal now been checked; when it says HIGH how much more often a goal follows; is that steady from season to season or does it come and go; and what the three findings from the scorecard about missed goals look like over the long history (do they hold).
ADD the result to /root/pe-queue/reports/goal_signal_scorecard.md under a heading 'Backtest' (keep the nightly table above it), not a new file. Commit and push: cd /root/pe-queue && git add reports/goal_signal_scorecard.md && git commit -qm "goal signal accuracy backtest" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q. Then end the session.
BRIEF
cat > /root/pe-builder/run_scoreback.sh <<'SH'
#!/bin/bash
CL=$(cat /root/pe-watchman/claude_path); ts=$(date -u +%F_%H%M)
cd /root/pe-sports/goaltrade && timeout -k 60 21600 "$CL" -p "$(cat /root/pe-builder/BRIEF_scoreback.md)" --allowedTools "Bash,Read,Write,Edit,Glob,Grep" --max-turns 400 --output-format text > /root/pe-builder/runs/${ts}_scoreback.log 2>&1
echo "scoreback session ended $(date -u '+%F %H:%M') exit $?" >> /root/pe-builder/sessions.log
SH
chmod +x /root/pe-builder/run_scoreback.sh
nohup setsid /root/pe-builder/run_scoreback.sh > /dev/null 2>&1 < /dev/null & sleep 15; echo "scoreback session started: $(pgrep -fc '[r]un_scoreback.sh')"
