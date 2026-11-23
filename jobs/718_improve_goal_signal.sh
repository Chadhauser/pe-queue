#!/bin/bash
# 718 (Mon 23 Nov 2026 05:44, Peter: "Can you improve goal signal?"). After the late-under session: version 3 of the goal signal,
# built beside the others and judged only by the nightly scorecard on matches it has not seen. No trading. Nothing deleted.
pgrep -f 'run_(lateunder|inplay|scoreback|scorecard)\.sh' >/dev/null && { echo "another session is running - waiting"; exit 75; }
cat > /root/pe-builder/BRIEF_signal3.md <<'BRIEF'
You are a Builder on Peter Edwards' trading server, session 25. Light on memory (football only, one day at a time). Work in /root/pe-sports/goaltrade (new files; do not edit the old signal or version 2 - build beside them). Read /root/pe-builder/BRIEF_league.md (HARD RULES), reports/goal_signal_scorecard.md (all of it, including 'What would make it sharper' and the Backtest section if present), reports/goal_signal_audit.md, reports/inplay.md, reports/late_under_717.md, reports/markets_recorded.md. Stay inside the API-Football plan (leave 40,000 calls a day for the collectors already running). No purchases, no sign-ups.
PETER'S QUESTION: can the goal signal be improved. What the real games showed: it is good at calling QUIET spells (LOW: 15% against 20% normal) and at HIGH late on (last 15 minutes 30% against 16%); its first-half HIGH is noise; the stats it uses cover only half the minutes and arrive about 1.4 minutes late; red cards are known on 4% of minutes; substitutions on none.
BUILD VERSION 3, each change kept only if it improves the scorecard on days it was not fitted on:
1. TWO QUESTIONS, NOT ONE: a 'quiet' model (no goal in the next 10 / 15 / 20 minutes) and a 'goal coming' model, fitted separately, because they are good at different things; and separate fits for first half, 45-70 and 70-90+, since the signal behaves differently in each.
2. BETTER FACTS, LIVE: collect match events live for every match we record on Betfair - goals, red and yellow cards, substitutions, penalties, VAR - from API-Football's live events (a collector of its own, plain loop, in /root/pe-mechanic/watch.list, cadence the call budget allows; measure and state its delay against the Betfair suspension). Line-ups before kick-off where available. Raise the share of minutes with live stats from 52% (say what limits it - leagues the feed does not cover, polling - and fix what can be fixed free).
3. MORE OF THE MARKET'S OWN VIEW, which is instant and covers every match: the goal expectation implied by ALL the goals lines together (0.5 to 5.5 and the newly recorded ones), correct score, both teams to score and team-goals markets; how that expectation moves against the clock over 5, 10 and 15 minutes; money traded and money waiting on each; where the markets disagree with each other.
4. THE GAME ITSELF: score state and who needs a goal, time since the last goal, the pre-match strength gap, which side is pressing (each side separately - and predict WHICH side scores next, scored on its own line).
5. KEEP LEARNING: refit once a week on a rolling window, automatically, always scored on the days after the fit; the nightly table gets a column per version (old, 2, 2b from order 717, 3) so the best one is visible without asking; when a newer version beats the one the trial rules use for a full week on LOW and on late HIGH, the trial's predictor switches to it and the table says so.
6. SAY WHAT WOULD HELP THAT WE DO NOT HAVE, with what each would add if it can be estimated: faster stats, a feed with substitutions and cards for the missing leagues, more weeks of data. No purchase proposed - just the list.
REPORT in reports/goal_signal_scorecard.md under a heading 'Version 3': one line - on the unseen days, HIGH / NORMAL / LOW against normal for version 2 and version 3 side by side, late HIGH separately, and which changes were kept and which were dropped (with the number that decided each). Commit and push: cd /root/pe-queue && git add reports/goal_signal_scorecard.md && git commit -qm "goal signal version 3" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q. Leave the events collector and the weekly refit running. Then end the session.
BRIEF
cat > /root/pe-builder/run_signal3.sh <<'SH'
#!/bin/bash
CL=$(cat /root/pe-watchman/claude_path); ts=$(date -u +%F_%H%M)
cd /root/pe-sports/goaltrade && timeout -k 60 21600 "$CL" -p "$(cat /root/pe-builder/BRIEF_signal3.md)" --allowedTools "Bash,Read,Write,Edit,Glob,Grep" --max-turns 500 --output-format text > /root/pe-builder/runs/${ts}_signal3.log 2>&1
echo "signal3 session ended $(date -u '+%F %H:%M') exit $?" >> /root/pe-builder/sessions.log
SH
chmod +x /root/pe-builder/run_signal3.sh
nohup setsid /root/pe-builder/run_signal3.sh > /dev/null 2>&1 < /dev/null & sleep 15; echo "signal3 session started: $(pgrep -fc '[r]un_signal3.sh')"
