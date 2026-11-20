# Builder handover 4 - 20 Nov 2026 (facts about the match joined to prices)
Money: £0, paper only. 720 ways decided by match facts added and tested; 2 pass the bar but fail the honesty check; 8 lean and survive it.

## Inventory in five lines (full list: reports/stats_inventory.md)
1. Live football facts: sofascore (expected goals, shots, on target, attacks, corners; stopped 9 Nov), espn (shots, on target, corners; stopped 15 Nov), api-football (score, on target, attacks, corners, a few red cards; running).
2. Every live feed is 1.3-2.7 min behind the market on a goal (median; 4-8 min p90), polled every 65-181 s: useless for reacting to goals, usable as a running record of chances.
3. Before the start: api-football results of 29 leagues 2016-20 Nov (+ expected goals from 2023), football-data with Pinnacle closing prices to 16 Nov; Understat, FTS, Elo snapshot all end before our prices.
4. Racing: racecards (draw, jockey, trainer, going) and results stop 8-9 Nov; tennis, cricket, golf have no live facts (results to Sep, cricket feed stopped 21 Oct, golf one fetch per event).
5. Not usable: af_events and line-ups are fetched after the match; team_profiles, jockey/trainer stats have no dates; no corners, bookings or next-goal market is recorded.

## The join (facts.py, prematch.py, racing_facts.py; links in grid/cache/fact_links.csv, alias table grid/team_alias.csv)
- Of our 2,341 football matches: 1,070 have some live fact; 456 have live expected goals; 609 live shots on target; 11 a live red card.
- sofascore 453 of 478 in our tape (25 rejected, names disagree); espn 268 of 299 (31 rejected); api-football 724 of 3,695 fixtures (0 ambiguous; most of the rest are leagues we do not record).
- Fair price before the start: 199 of our matches (406 markets). Racing facts: 1,881 runners on 7 days (draw known 620).
- Never guessed: kick-off within 30 min AND both names (alias, exact or strict spelling), exactly one candidate; women's/youth/reserve words must agree (the old matcher dropped them). 40 links checked by eye: all right.
- Known-at rule: a fact is visible only from (received by our server + 5 s), strictly before the order. test_known.py: 15 new hand-worked checks (a fact after the order, or exactly at it, is invisible; extra delay; stale fact; side-relative numbers; minute anchor; fair-price edge). ALL PASS, 128 checks in all (session 5 added some too).
- Feed minute never ran ahead of the real clock (checked on every source; two early kick-offs only).

## Ways added (registry 52857-53576, all tested 31 Oct-19 Nov, 0 errors)
In play: lay the draw / back the stronger side / back overs when level and ahead on chances (250), the mirror when nothing is created (48), behind on goals but ahead on chances (48), goal against the run of play (24), over/under from the rate of chances (64), red cards (6). Before the start: fair price, 3 markets x 1 h/10/2 min x 5 margins x both sides x hold or close after the first event (180). Racing facts on 6 price ways (78). Passing price-only ways with a fact as a filter (22).

## What passes or leans (after removing each row's best day and 3 biggest winners)
- PASS on the bar but NOT real: 53484 and 53489 (racing long shots 10 min before, with a course or going fact): -£1,217 and -£407 without best day and top 3 winners. They went to paper by the rule; their racing facts stop 9 Nov, so forward paper cannot fill until racecards return.
- Lean and survive: lay the over at minute 30 when level and few expected goals (53109: 121 orders, +£660 left; 53111: 157, +£653; 53238: 52, +£573), the same at minute 45 (53123: +£244), back the side ahead on target at minute 70 when level (53075: 64, +£222), lay the draw at minute 30 when one side leads on target by 2+ (52922: +£145), way 1134 only where the laid team is not behind on target (53566: +£135). All far under 300 orders, mostly 2-9 Nov.
- Fair price before the start: -£84,092 a month across 180 ways. The model is calibrated and steady out of sample, but less accurate than Pinnacle's closing price every year (1.020 against 0.994 miss score, 34,492 matches): reports/prematch_model_check.md.
- Combine: knowing the match changes the price-only ways only in samples of 12-124 orders; nothing settled (detail at the end of stats_inventory.md).

## Blocked (reports/ideas_blocked.md, session 4 table)
Live expected goals after 9 Nov (collector stopped); goal reaction (feeds too slow); red cards (11 matches); corners/bookings and next-goal markets (not recorded); 24 h prices; team news (fetched after the match); fair price outside 29 leagues; racing facts after 9 Nov; tennis, cricket, golf live facts.

## Running / not done
- run_league.sh now calls facts.py, prematch.py, racing_facts.py each pass, but the loop (pid 111860) read the old script: it takes effect when it is next restarted. Not restarted by me (it must not go down).
- Session 5 worked in the same directory at the same time (paper trader). Both kept to in-place edits; grid/SESSION4_NOTE.md lists what I changed. Its exit columns in onetest.py are intact; tests pass.
- Not done: tennis rank against price (surname-only names, ranks 2 months old); model-against-Betfair check on all days (stopped for memory, 8 Nov only: Brier 0.208 against Betfair's 0.195).

## Next session, first
1. Get the sofascore (ip_stats) and espn collectors running again, and racecards daily: without them the fact ways stop at 9-15 Nov.
2. Restart run_league.sh between passes (`pgrep -f "[r]un_league.sh"` alone, then kill and relaunch) so facts refresh each pass.
3. Re-run robust.py on the lean rows each week; only rows that survive removal of the best day and top 3 winners count.
