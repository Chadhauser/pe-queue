# The goal trade (session 12) — FIRST VERSION, NOT A RESULT YET

**Verdict: not yet known. The measurement is running now; this page will be replaced with the numbers tonight.**

Tier one (trading). Money: £0. Paper only, no order endpoint touched.

What is built so far (in /root/pe-sports/goaltrade):
1. `gt_build.py` makes one row per match per minute of play, holding everything known at that minute and what happened next. Every trade runs through the grid's own fill rules (onetest: £2 shown, £50 cap, 2% commission on net winnings, an exit that cannot fill is held to the result).
2. When each goal happened: our recorded prices keep quoting through a goal (the book reopens wide), so the grid's 20-second-gap detector finds only about 70% of goals. The score feeds (api-football, ESPN, sofascore) say a goal happened and who scored it. The tape then gives the exact moment: the biggest price jump in the 10 minutes before the feed reported it. Tested on 3 Nov: goal counts match the final score in 100% of matches, the Over 2.5 result agrees in 100% (60 of 60), the moment always falls before the feed reported it, and the over price really shortened across 88% of the timed moments.
3. A bet goes down only if no goal comes in the next 10 seconds (Betfair holds in-play bets for about 5 seconds and cancels them if the market suspends). After a goal we close on the first settled price after the market reopens, within 3 minutes.

Limits found so far:
- Only matches with a full score feed can be used: about 40% of the matches we record.
- Until 17 Nov we recorded only the 2.5 and 4.5 goal lines, so "the lowest line still open" is usually 2.5. All lines were recorded from 17 Nov, but only for 35 to 54 matches a day.
- We do not record a next-goal market.
- Session 11's bookmaker prices: no in-play rows yet (its collector started today at 16:04 UTC), so trade (d) cannot be tested.

Next: the break-even table, the predictor, the trades, then this page gets the verdict.
