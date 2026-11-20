#!/bin/bash
# 687 (Fri 20 Nov 2026 14:47, Peter: "why am I coming up with the ideas ... I should be stopping you from going overboard on ideas").
# Starts one builder session that loads the league table with every angle below as rows in the ONE TEST, and leaves a weekly idea
# list file so new ways keep arriving without Peter. Paper only. No orders. Nothing deleted.
B=/root/pe-builder
cat > $B/BRIEF_ideas.md <<'BRIEF'
You are the Builder on Peter Edwards' trading server, session 3. Started once. Do the job, leave ordinary background processes running, write your handover, stop. No idle loops; long runs go to the background with nohup + nice.
FIRST read /root/pe-queue/reports/builder_handover_2.md and /root/pe-builder/BRIEF_league.md (Peter's instruction and the hard rules there apply to you unchanged), then the code in /root/pe-sports/grid/ (onetest.py, arbs.py, ways.py, league.py, test_known.py). Reuse it.
WHY THIS SESSION: Peter had to suggest club bias himself and it was not in the table. That must not happen again. The league table must be over-supplied with ideas from us. Your job is BREADTH: register every angle below as ways of earning (one plain sentence each, source a/b/c, origin named), with every sensible variant as its own row, and let the existing loop test them all in the one test. Where onetest.py cannot express an angle, extend it with a hand-worked check in test_known.py first. Where the data for an angle is not recorded, do not fake it: write the angle into reports/ideas_blocked.md with the one thing that is missing.
ANGLES (do not stop at this list):
1. Crowd and club bias (Peter, 14 Oct). Lay the popular side at and before the start, held to the result and also closed after the first goal: the biggest clubs in each league (by matched money on their matches, measured from our own data, not a hand list), home and away separately, televised kick-off slots (evening and Sunday afternoon) against the rest, derbies, national teams, the favourite in the biggest-money match of each day. Same for tennis (the famous name against the lesser one), racing (the favourite ridden or trained by the biggest names; the most-backed horse of the day), cricket and golf (the star). Also the mirror: back the unfashionable side.
2. Price drift before the start. Compare the price 24 hours, 6 hours, 1 hour, 10 minutes and 2 minutes before the start: does the crowd side keep shortening (ride it and close) or overshoot (fade it)? Split by how much money has traded.
3. Favourite and outsider bias by price band, every sport and market type: lay the outsiders, back the short ones, and the reverse, in every band, held and closed.
4. Overreaction in play. After a goal, a red card, a break of serve, a lost set, a wicket, a faller or leader change: lay the side the crowd has just piled into and close 30 s, 2, 5 and 10 minutes later; and the reverse. Split by how early in the match it happens and by the price before the event.
5. Comeback prices. When the pre-start favourite goes behind, back it at the drifted price (and lay it) - football, tennis by set, cricket, basketball by quarter.
6. Time decay. Lay the draw, lay overs, back unders, lay the next-goal and correct-score outcomes that need a goal, from each ten-minute mark, closed at later marks and on a goal.
7. Offering prices (how exchange traders and bookmakers earn): rest a back and a lay a tick or two apart and earn the gap - racing in the last 30, 10, 5 and 2 minutes, greyhounds, thin football leagues, lower tennis, every other market type with a wide gap; one-sided offers just inside the best price; offers rested far from the price to catch a spike in play.
8. Weight of money and order flow: when money waiting to back is 2x, 3x, 5x the money waiting to lay (and the reverse), follow and fade over 30 s, 2 and 10 minutes; large single trades; sudden gaps.
9. Markets that must agree, same match: match odds, double chance, draw no bet, correct score, over/under at every line, both teams to score, half time, half-time/full-time, Asian handicap, next goal, win and place in racing, set betting against match odds in tennis. Trade the one out of line; also the one that is slow to move after an event on the other.
10. Same event on other exchanges: Betfair against Smarkets and Matchbook, take both sides when they cross after each exchange's commission; offer on the slower one at the faster one's price; which exchange moves first.
11. Calendar and clock: day of week, kick-off hour, early-season and late-season, midweek against weekend, first match after an international break, race type (handicap or not, field size, distance, going where recorded), surface and round in tennis, format in cricket.
12. Thin against deep: the same rule in the biggest-money matches and the smallest; leagues ranked by money traded.
13. Bookmaker habits: lay every selection at or just before the start at the price on offer when the whole market adds up to over 100% on the lay side by enough to beat commission (a book laid round); dutch all outcomes when the back side adds to under 100%.
14. Racing in running: back-to-lay front runners, lay-to-back hold-up types, lay at very short prices in running, back at very long ones, by distance and field size. Check recorder delay before believing any in-running row.
15. Greyhounds, basketball, American football, ice hockey, baseball, rugby, darts, snooker, golf: run angles 3, 4, 5, 7 and 9 wherever a single day of real prices exists; show the real count.
16. Anything the data shows that fits none of these. Look at the 50 best and 50 worst rows already in the league and ask what they have in common; register the pattern as new ways.
ALSO: (i) merge rows that are the same bets (same orders on 90% or more) so the table counts an effect once and marks the others 'same as way N'; (ii) a paper way that later fails the test is taken off paper and marked failed; (iii) write /root/pe-builder/IDEAS.md, the running list of angles with a tick for 'in the table', so the next session adds to it; (iv) add one line to the top of reports/league_table.md: 'Distinct effects passing: N'.
HONESTY as before: real counts, the bar is not lowered, a row that looks too good gets its flaw found before it is reported. Recorded data is about three weeks.
WHEN YOU STOP: write /root/pe-queue/reports/builder_handover_3.md, plain English, under 45 lines: angles registered and ways added per angle, angles blocked and the one thing each needs, what is running, what the next session should do first. Commit and push: cd /root/pe-queue && git add reports/builder_handover_3.md reports/ideas_blocked.md reports/league_table.md reports/paper_forward.md reports/grid_progress.md 2>/dev/null; git commit -qm "builder session 3: idea engine" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q. Then end the session.
BRIEF
cat > $B/run_builder_ideas.sh <<'SH'
#!/bin/bash
CL=$(cat /root/pe-watchman/claude_path); ts=$(date -u +%F_%H%M)
cd /root/pe-sports/grid && timeout -k 60 21600 "$CL" -p "$(cat /root/pe-builder/BRIEF_ideas.md)" --allowedTools "Bash,Read,Write,Edit,Glob,Grep" --max-turns 600 --output-format text > /root/pe-builder/runs/${ts}_ideas.log 2>&1
echo "builder ideas session ended $(date -u '+%F %H:%M') exit $?" >> /root/pe-builder/sessions.log
/root/pe-builder/progress.sh
SH
chmod +x $B/run_builder_ideas.sh
if pgrep -f '[r]un_builder' >/dev/null; then echo "a builder session is still running - not starting a second one"; else nohup setsid $B/run_builder_ideas.sh > /dev/null 2>&1 < /dev/null & sleep 40; echo "builder session 3 started: $(pgrep -fc '[r]un_builder_ideas.sh')"; fi
