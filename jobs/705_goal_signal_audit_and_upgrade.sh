#!/bin/bash
# 705 (Sat 21 Nov 2026 16:01, Peter: "Audit the goal signal to see what can be added or improved"). Runs after the goal-trade
# session ends (it uses its findings). Audits the existing goal signal's code and stored history, then upgrades it as a NEW
# version alongside the old one. Paper only. No orders. Nothing deleted; the old signal is not edited.
[ -f /root/pe-builder/BRIEF_goaltrade.md ] || { echo "goal trade brief missing"; exit 75; }
pgrep -f '[r]un_goaltrade.sh' >/dev/null && { echo "goal trade session still running - waiting"; exit 75; }
cat > /root/pe-builder/BRIEF_goalaudit.md <<'BRIEF'
You are a Builder on Peter Edwards' trading server, session 13. Work in /root/pe-sports/goaltrade (new files, schema 'goaltrade'). Read first: /root/pe-queue/reports/goal_trade.md and books_and_goal_signal.md, then the existing goal signal: /root/pe-brain/repo/brain/ (monitor_ht.py, pattern_matcher.py and what they import) and its tables. HARD RULES: paper only; never an order endpoint; nothing deleted; do NOT edit the old signal's code or tables - the upgrade is a new version beside it; credentials only through /root/pe-queue/runner/creds.py; never print a token; no purchases.
THE CHAT'S AUDIT OF THE DESIGN (check each against the code and the data; confirm, correct or add):
 1. Its thresholds were set by hand and never fitted or scored: pre-match score 4 of 6, a 5% price drop in 60 s or 5 shortening ticks, minutes 45-85, a 20-minute cooldown, 11 leagues.
 2. It holds a large history nobody has used honestly: goal_live_predictions (about 2.3 million rows), goal_backfill_predictions (71,065), goal_events (113,281 goals), goal_match_stats, goal_poisson, goal_league_calibration, 1,301 alerts. Score all of it: predicted goal chance against what happened, in ten bands, by minute and score, first half of the dates against the second.
 3. Its price trigger may fire AFTER the information is in the price (a price that has just shortened 5% may be the goal itself, seen first by people at the ground): measure the price move in the 1, 3 and 10 minutes after each trigger, net of the gap.
 4. Its trade has no stop: 'back the next over line, exit on a goal or at 82 minutes'. No drift cost counted, no side, no first half.
 5. Its inputs died silently for two weeks (stats 8-9 Nov, goal events 8 Nov) while it kept reporting as running; logged errors (duplicate key, a format error) lost alerts. It needs a gate: no alert when any input is stale, and a line in /root/pe-mechanic/watch.list for each input.
 6. Its stats are 1.3-2.7 minutes late; the market's own signals are instant and cover every match.
 7. It compares stats with fixed levels, not with what the PRICE already expects. The right question is 'do the stats say more goals than the over/under line implies right now'.
WHAT TO ADD (test each as an input to the goal-trade session's predictor, on the unseen half, and keep only what adds uplift): the goal expectation implied by the current over/under prices as the baseline; pressure in the last 5/10 minutes against the match's own earlier rate; which side needs a goal (favourite behind or level late; cup second legs if known); red cards and substitutions where recorded; time since the last goal; set pieces (corners in the last 5 minutes); the correct-score and match-odds markets moving without the over/under moving; a bookmaker's over price left behind (session 11's table); the referee and league scoring rates already stored; every match we record on Betfair, not 11 leagues; both halves of the match.
DELIVER: (a) goal signal version 2 as a paper-only program beside the old one: scores every live match every cycle, writes its top band to goaltrade.signal_v2 with the reason in plain words, refuses to fire on stale inputs, in watch.list; (b) version 1 against version 2 on the unseen dates: goals within 10 minutes after a signal against the base rate, and the goal trade's £ kept per £100 with a stop, both halves; (c) wired into the goal-trade paper trader if that exists.
WRITE /root/pe-queue/reports/goal_signal_audit.md, plain English, one screen: line 1 = can version 1 predict a goal (uplift over the base rate, both halves); line 2 = version 2's uplift and what was added that mattered; line 3 = does the goal trade pay with it after costs, yes / not yet / no; then one line per audit point (confirmed / wrong / fixed), then what would improve it most that we do not have. Commit and push: cd /root/pe-queue && git add reports/goal_signal_audit.md && git commit -qm "goal signal audit and version 2" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q. Then end the session.
BRIEF
cat > /root/pe-builder/run_goalaudit.sh <<'SH'
#!/bin/bash
CL=$(cat /root/pe-watchman/claude_path); ts=$(date -u +%F_%H%M)
cd /root/pe-sports/goaltrade && timeout -k 60 21600 "$CL" -p "$(cat /root/pe-builder/BRIEF_goalaudit.md)" --allowedTools "Bash,Read,Write,Edit,Glob,Grep" --max-turns 600 --output-format text > /root/pe-builder/runs/${ts}_goalaudit.log 2>&1
echo "goal audit session ended $(date -u '+%F %H:%M') exit $?" >> /root/pe-builder/sessions.log
SH
chmod +x /root/pe-builder/run_goalaudit.sh
nohup setsid /root/pe-builder/run_goalaudit.sh > /dev/null 2>&1 < /dev/null & sleep 15; echo "goal audit session started: $(pgrep -fc '[r]un_goalaudit.sh')"
