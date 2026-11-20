# Builder handover 3 - 20 Nov 2026 (idea engine: breadth)
Money: £0, paper only. League so far (12 of 20 days in this pass): 24 ways pass (300+ orders, profit in both halves), 'Distinct effects passing: 22' - an UPPER bound: ways tested before order keys existed (the top 5 racing long-shot rows, same entries) get their keys from tools/backfill_keys.py, still running, and the loop's end-of-pass table (about 23:00 UTC) merges them. No session-3 row passes yet.

## Angles registered (ways added; one plain sentence each, source and origin named; all through the one test)
1. Crowd and club bias (Peter, 14 Oct): 433. Popular side = most money matched on a club's EARLIER matches in our own data (no hand list): more-followed side, top 10/25 clubs, top 3 in its league, home/away, national teams, derbies (hand list of 50), kick-off slots; lay held or closed after the first goal, plus mirror backs. Famous name at 30 s in (tennis, cricket, darts, hockey, basketball); golf star; racing favourite by top jockey/trainer; most-backed horse.
2. Drift before the start: 342. 3. Price bands, every sport and market type: 1,296. 4. Overreaction in play: 360. 5. Comeback prices: 123.
6. Time decay: 321. 7. Offering prices: 214. 8. Weight of money, big trades, sudden gaps in the book: 396. 9. Markets that must agree: 15 new pairs.
10. Other exchanges: 34. 11. Calendar and clock: 122. 12. Thin against deep: 32. 13. Book laid round / dutch: 30. 14. Racing in running: 62.
15. Other sports: inside the rows above (basketball 220, hockey 125, American football 109, cricket 107, darts 101, snooker 63, others 24-40).
16. Patterns in the 50 best and 50 worst rows: 124. They were chosen from these same days, so they are tested ONLY on days after 20 Nov (the first 124 were circular and are retired as 'replaced').
Total session 3: 3,904 new rows + 124 replacements; registry 7,523 ways. Full list with ticks: /root/pe-builder/IDEAS.md.

## Built (in /root/pe-sports/grid/, backups *.bak_session3)
- onetest.py: new moments (sharp move within a minute, big trade, sudden gap in the book, 30 s after the NEXT event, drift from any moment), filters (money matched, most-backed runner, favourite at an earlier moment, crowd move across an event, dates, league/popularity/jockey facts), offers rested far from the price, per-rule freshness.
- arbs.py: whole market adding up wrong (lay all over 100%, back all under 100%) on a shared 5 s grid; 5 new market pairs. meta.py (new, in run_league.sh): facts known before the start, per day.
- league.py: order keys per way and day; rows with 90%+ the same orders marked 'same bets as way N' (way_same); first line 'Distinct effects passing: N'; a paper way that fails comes off paper (paper_end: 11 so far).
- test_known.py: ALL PASS, 96 hand-worked checks (59 before + 37 new).

## Flaws found before reporting
- Angle-16 rows were circular: retired, replaced by forward-only rows. Jockey ranks were alphabetical, most-backed was ranked after the price filter, going was free text, date filter crashed: all fixed and tested.
- Passing rows hang on single days: way 3218 (top row) made £1,612 of its £1,686 on 2 Nov; without its best day 41, 173 and 1401 are flat too. Only 1134, 2924, 404, 479 stay positive. Do not report any as money.
- Whole-market tennis laying (way 11779, 11 orders on 2 Nov, +£20) comes from the two players' quotes arriving 0.7 s apart in a fast in-play move: treat as stale-quote risk, not money, until it is seen on paper.

## Blocked (reports/ideas_blocked.md, the one thing missing each)
24 h and 6 h prices; pre-start prices in in-play-only sports; 32 s in-play polling outside football and racing; greyhounds; racecards stop 9 Nov; TV listings; red cards; set/point/quarter scores; racing positions; next-goal, set-betting and pre-off place markets; Smarkets/Matchbook trades and 24 s polling (lead-lag); a season of data; tennis surface and round.

## Running
run_league.sh loop (pid 111860; cache, meta, ways, league, commit, sleep 6 h), on the new code since 15:57 UTC; about 15-25 min a day, so this pass ends around 23:00 UTC and commits league_table.md itself. Angle 10 rows are tested from 3 Nov, angle 9 from 17 Nov (match links start then), the gap rows from the next pass. run_grid_recorded.sh, grid_history.py untouched. tools/backfill_keys.py (one-off) gave old passing rows their order keys.

## Next session, first
1. Read league_table.md (the Distinct line, 'same bets as way N') and league.log for errors; check every session-3 row near 300 orders (cricket fade 10636/10637 are at 50, profit in both halves).
2. For every passing row, drop its best day and its 3 biggest winners: report only what survives.
3. Add the unticked items in IDEAS.md (draw no bet / Asian handicap with refunds; goal against card from goal_timeline; a stake ladder per passing way).
