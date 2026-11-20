# Builder handover - 20 Nov 2026 (recorded-prices grid)
Money: £0 so far, paper only. Nothing here has passed the proof gate.

## What I built (all in /root/pe-sports/grid/)
- engine.py: the grid logic, with no database. Covers points, real-price stakes, families 1 (hold), 2 (in and out) and 3 (offer the price), depth, direction and halves by date.
- test_known.py: a hand-worked test. `python3 test_known.py` gives ALL PASS (35 checks, 0 failed, run 20 Nov after the last change).
- settle.py: settles markets read only. Betfair uses listMarketBook into book_result (insert only); 35,713 of 36,097 recorded markets are settled. Smarkets uses its own public contracts endpoint (state_or_outcome) into xx_result. Matchbook is matched to the Betfair result of the same match (kick-off within 10 min, both team names must agree, one match only) into xx_result.
- grid_recorded.py: loads one market start-day per source, runs the engine and writes the results. Resumable through grid_rec_done(source, day).
- report_recorded.py: writes reports/grid_recorded.md. /root/pe-builder/progress.py now adds grid_agg2 to its totals and top 20 (the original is saved as progress.py.orig_20nov).
- run_grid_recorded.sh: the loop. Grid, then settle, then commit the report, then sleep 6 h, so new days join the grid up to 25 Nov.
- New tables: grid_agg2 (grid_agg's columns plus depth, stake £, pnl £, nloss, by DAY), grid_fill (offer fill rates), grid_rec_done, xx_result. I wrote no recorded rows into grid_agg. Its month column would leave only one half on 3 weeks of data, and it has no depth column.

## What the test proves
- Trap 1: when there is no fresh exit price, the bet is held to the result. Test: B backed, no exit, B loses, -£50.
- Trap 2: stale quotes are not prices. A dead runner showing only a back at 1.02 is not read as a 98% chance (this was a real bug found on 18 Nov data and fixed).
- Trap 3: £2 minimum on offer, £50 stake, £50 lay liability and 2% commission, each worked to the penny. A part exit is part closed and part held: +£6.6314.
- The engine also enforces the £1 Betfair minimum stake, so lays above about 51 are not placed.
- Trap 4: depth is thin under £2k, medium up to £20k, deep from £20k (matched £ at the point).
- Trap 5: halves are by date, and never-lost slices are flagged. £ a month = £ over all of the source's days x 30.4.
- Family 3: an offer fills only when a later trade goes THROUGH it; a trade AT the price does not fill.

## Running now
- run_grid_recorded.sh, restarted about 08:10 UTC on clean tables. Watch.list line "gridrec". grid_history.py was left running, untouched.
- Each Betfair day takes 2-5 min (5 GB peak memory); Smarkets and Matchbook days take about 1 min.
- First pass: Betfair 31 Oct-18 Nov, then Smarkets and Matchbook 3-18 Nov. It should finish about 10:30 UTC (log times are CET, UTC+1); after that it adds a day every 6 h.
- Checked by me: 31 Oct, 10 Nov and 18 Nov (Betfair), 16 Nov (Smarkets and Matchbook). Results by price band look sane (backs at 90-100% lose about 1 per £100), and 10 Nov gave identical results twice.

## Not done yet, and why
- Matchbook: 349 of about 810 markets settled. Matchbook gives no winners, and Betfair match-odds names exist only from 14 Nov (stream) and 17 Nov (book_snap), so Matchbook 3-13 Nov is all unsettled.
- No family 3 on Smarkets or Matchbook: the tapes have no traded prices (ltp is empty). They also have no matched volume, so depth = 'no volume data'.
- The 24 h and 6 h points exist only on book_snap (football from 17 Nov) and Matchbook. The stream records only the last hour before the off.
- liq_sample and railway_final are not used: liq_sample has no selection ids, and the stream already covers football in-play.
- Recorded data covers only about 3 weeks, so few slices reach 300 bets yet. The full test starts on 18 Nov data (48 slices with 300+ bets, 0 profitable in both halves); it grows daily.

## For the next builder
- Never `pkill -f "python3 grid_recorded.py"` from a shell whose own command contains that text, because it kills your own shell. Use `pkill -f "[r]un_grid_recorded.sh"`.
- To redo a day, delete its row in grid_rec_done. Recent days with more than 20% unsettled re-run by themselves.
- Smarkets sizes are taken as £ on offer, as the recorder stored them. Not verified against the Smarkets API.
- Check in-play horse racing for recorder latency before trusting any positive racing slice. 10 Nov showed +222 per £100 on 288 bets, driven by 2-3 long-shot winners.
