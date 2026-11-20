# Builder handover 2 - 20 Nov 2026 (one test, one league table)
Money: £0, paper only. 11 ways pass the league bar on the 8 of 20 days tested so far. They are ONE effect (laying football selections priced at a 20-30% chance around kick-off, mostly the draw), about 2.3 standard errors from zero on 4 real days. On forward paper from 20 Nov, 0 of 100 settled. Not proven.

## What I built (all in /root/pe-sports/grid/)
- onetest.py + arbs.py, THE ONE TEST: `run(rule, days)` returns the orders that would really have filled, with profit after 2% commission per market. Take: best price, only the money shown, £2 minimum. Offer: fills only on later trades THROUGH the price, only for the money matched on those trades. £50 a bet and £50 lay liability (closing bets too), £1 minimum stake. An exit that cannot fill is held. Stale quotes, and stream quotes delayed over 2 s, are not used. Kinds: take/offer; hold, close at a later moment, or rest a closing order; both sides at once; after an in-play event (a suspension gap of 20 s or more with a 10% price move); after a big in-play move; one outcome in two places (Betfair against Smarkets or Matchbook; match odds against double chance or correct score; half time against half-time/full-time; under 2.5 against correct score).
- cache.py: each exchange-day loaded once to cache/<exchange>_<day>.parquet (peak about 8 GB; it waits until 11 GB is free).
- ways.py: registry table earn_ways. One line adds a way: `add("Plain sentence.", 'a', "origin", {rule})`. It re-registers new recorded-grid slices (100+ bets) on every loop.
- league.py: tables way_day, league, paper_start, paper_forward; writes reports/league_table.md (every way, passing first, header counts) and reports/paper_forward.md.
- run_league.sh: the loop (cache, register, league, commit reports, sleep 6 h). watch.list line "league" (backup watch.list.bak_session2_20nov).
- /root/pe-builder/progress.py rewritten (backup .bak_session2_20nov): the league summary every hour (cron is unchanged); history appears only as a count of ideas. friday_four.py line 3 now reads the league (backup .bak_session2_20nov; compiles; prints 4 lines).

## Bug found in session 1's code, fixed
- grid_recorded.tf: this pandas reads the archive's t/f in-play column as 'str', not 'object', so every archived pre-start quote (2-13 Nov) was read as in-play. Fixed (backup grid_recorded.py.bak_session2_tf). rerun_archive_days.sh re-runs those days through grid_recorded.py --day once the league's first pass ends. Until then, grid_agg2 rows for 2-13 Nov are wrong.

## Tests: python3 test_known.py gives ALL PASS (59 checks, run 14:06 UTC)
Hand-worked one-test cases: take and hold (+£29.40; lay with capped liability +£15.3125); take in and out (+£3.2667); an offer filled only for money traded through it (£30, +£29.988); an offer only touched, which must NOT fill (0 orders); an exit that cannot fill, held (-£20, -£50); a part-filled resting exit (+£2.2867); two-market dutch (+£3.4738); two-exchange (+£3.0804); market making both sides (-£0.2051); goal detection; league halves, £ a month, never-lost flag, the 300 bar. Plus session 1's 35 checks. A speed change was checked against the old code on 40 real ways: identical.

## Numbers now
- Ways: 3,495 (a 381, b 3,059 of which 143 are history ideas, c 55). Tested 3,299; 4 cannot be tested (listed with the reason). 19,398 small grid slices are not registered yet (fewer than 100 bets).
- Flaws checked: the best non-passing rows (long-shot horses, +£96 per £100) rest on 7 real winners where about 5 were expected; prices were fresh and on offer. Two-market checks found almost no crosses (1 order on 18 Nov), so the test is not inventing profit from stale prices.

## Running
run_league.sh (first pass on 7 Nov at 14:06 UTC; about 13 minutes per big day, so it should finish around 17:30 UTC and commit the full table); rerun_archive_days.sh (waiting for that); run_grid_recorded.sh (asleep between runs). grid_history.py finished all 29 market types at 10:59 UTC by itself.

## Not done, and why
- Offer fills count all money matched since the previous quote when the trade price is through, which can overstate fills a little. Commission is not netted across several orders in one market, which overstates costs a little.
- Cannot be tested yet: offering on Smarkets or Matchbook (no trades recorded there); a fair-price model for thin markets (not built).
- Tennis serve and break points, and racing positions, are approximated by price moves (no point or position data). Goal detection is not yet checked against goal_timeline.
- Smarkets 3-13 Nov and most of Matchbook are unsettled (a settle.py limit), so those days give no orders.
- A paper way that later fails stays on paper; overlapping ways are not merged.

## Next session, first
1. Check that league.log ends with "league:" and read league_table.md: do the 11 still pass on all 20 days?
2. Merge overlapping ways (the same bets) into one row before adding up £ a month.
3. Check goal detection against goal_timeline; speed up league.py (about 13 minutes per day).
