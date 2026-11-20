0 paper orders were placed since 19 November because forward paper was only written by the 6-hourly league pass, for days strictly AFTER 19 Nov, and only once cache.py had built the day, which it does 36 hours after the day ends; so 20 Nov could not show before about midday 21 Nov plus a pass, and 19 Nov never counted. (The CEO's reading was right; the correction is "36 hours", not "tomorrow", and that 19 Nov itself was excluded.)
The paper trader started at 19:21 UK on 20 Nov (backfill run 19:13-19:20). Trades written: 1,888 for 19 Nov and 1,959 so far for 20 Nov, one row per way. Shown once in the files: 820 on 19 Nov, 951 on 20 Nov, plus 3 placed late on 18 Nov in markets starting on the 19th.
Money (paper): 19 Nov -£2,074.91 and 20 Nov -£1,512.68 so far (592 of 951 settled), counting each bet once. Running total since 19 Nov: -£3,637.86. Counted per way: -£9,727.82 (19 Nov) and -£4,710.04 (20 Nov so far).
Biggest loser: the five 'back a 0-10% chance 10 minutes before' racing ways. They place the same bets, each is about -£2,700, and the league test had them at about +£8 per £100. They back outsiders, so their bar is 1,000 (288 settled each).

Built: papertrader.py + run_papertrader.sh (nohup, nice, 10-minute sleep loop, in watch.list). It runs the 24 paper ways through onetest.run on today's live tables, reading only rows stamped before the cut (now - 60 s).
Table grid.paper_trades. public.paper_trades already existed (someone else's, 1 row from May) and was left untouched. A trade is written once; after that it can only be closed or settled.
Files: trades_today.md and trades_YYYY-MM-DD.md, rewritten every 10 minutes and pushed at most every 30 minutes and at 23:55 UK. paper_forward.md counts each way against its own bar (1,000 for ways that back 5.0+, 100 for the rest). The league loop writes league_top10.md.
Edits (backups *.bak_session5): onetest.run now also returns the exit price, stake and moment (fills and profit unchanged). cache.load_betfair has a live/cut mode (defaults unchanged). league.py writes top10 and takes the gate from paper_trades.

Checked:
- test_known.py ALL PASS, including 20 new hand-worked checks: no trade before its entry moment, never the later better price, close and settle worked by hand (+£490.00 / +£539.00), written once, same bets shown once, the outsider bar.
- 19 Nov replayed through the paper trader against the league test: 1,809 of 1,809 orders the same in price, stake and profit (-£9,727.82 both). The 79 extra are in two markets with no result, which the league drops (tools/replay_compare.py).
- Today on real data at cuts 13:00, 15:30, 17:30 and 19:10: 0 trades placed after their cut, 0 entry quotes stamped after placing, 0 earlier trades changed later (lookahead_20nov.log).

Not done / watch:
- Results only reach book_result through settle.py in run_grid_recorded.sh (every ~6 h; last run 16:45 UTC), so evening trades show 'open' for hours. That loop was not changed.
- The running league process still has the old code. At the end of this pass it will write paper_forward.md once in the old format; the trader rewrites it within 10 minutes. top10 and the new gate start with the next pass.
- Behaviour change: under the existing gate rule, at the next pass five lay ways that are past 100 settled and losing (2924, 3819, 4683, 2908, 4020) will come off paper. Stop it before then if that is not wanted.
- The 79 orders on 19 Nov in markets with no result stay open. The top 5 in league_top10 are the same bets (their order keys are still being backfilled). Session 4 was editing onetest, league and test_known at the same time; my edits were re-checked afterwards.
