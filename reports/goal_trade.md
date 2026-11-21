# The goal trade — NOT YET (session 12, 21 Nov 2026)

**NOT YET.** Backing "a goal is coming" loses after costs on unseen days. To break even our predictor has to beat the normal goal rate by **13 to 16 points**. It does **+2 (5 min), +6 (10 min), +8 (15 min)**. Closest: minutes 45-75, 10-min hold, where it does +10.8 against about 9 needed and loses **£0.51 per £100** (74 orders), about break-even but not yet profit. Nothing put on paper (the rule was paper only on a YES).

Tier one. Money: £0. Data: our recorded prices 2-19 Nov (score feeds cover 719 of 2,341 matches; none on 10-12 Nov). Session 11's bookmaker table: 0 in-play rows (started 16:04 today), so the bookmaker version (d) could not be tested.

## The arithmetic (back the over on the lowest open line; out at the goal or after N minutes; per £1 staked; 719 matches)
| N min | chance of a goal (base) | lost if no goal | won if a goal | gap in+out | break-even chance | points needed | every minute, per £100 |
|---|---|---|---|---|---|---|---|
| 5 | 11.4% | 22p | 69p | 4.6p | 24.1% | +12.7 | -£11.6 |
| 10 | 22.2% | 34p | 58p | 4.6p | 36.8% | +14.7 | -£13.4 |
| 15 | 31.6% | 44p | 49p | 4.7p | 47.3% | +15.7 | -£14.7 |
| 20 | 39.4% | 54p | 44p | 4.8p | 55.3% | +15.9 | -£15.5 |

Cheapest minutes: 45-75, where it needs +7 to +10 points. Dearest: 75-90, where it needs +23 to +34.

## The predictor (fitted on 2-8 Nov, scored on 9-19 Nov)
- Top tenth, goal within 10 min: predicted 32%, actual 30%, against 24% normal for its minute and score. Its ten bands rise steadily from 10% to 30%, so it is real, just not big enough.
- The market's own signals do almost all of it: money traded per minute (+5 points by itself on unseen days) and the price refusing to drift (+3).
- Shots, shots on target, xG, dangerous attacks and corners add nothing on top (+5.8 with them, +6.3 without).
- **The goal monitor's own p(goal) has no signal**: on its own it ranks matches no better than chance (score 0.50, where 0.50 means none and 1.0 means perfect), and its top tenth scored *2 points below* normal. Adding it to the rest moves results by 0 to 1 point.
- Which side scores: getting the side wrong is the real risk. When the other side scores we lose **£71 to £81 per £100**.

## The trades (fill rules: price on offer, money shown, £50 cap, 2% commission; unseen days 9-19 Nov, one position per match at a time)
| trade | best form | orders | per £100 | worst day | without best day |
|---|---|---|---|---|---|
| (a) back over, goal coming | 10 min, 10% stop | 325 | -£7.8 | -£354 | -£13.3 |
| (a) lay under (lay < 3.0) | 15 min, 10% stop | 205 | -£16.9 | -£454 | -£21.2 |
| (a) minutes 45-75 only | 10 min, 10% stop | 74 | +£7.7 | -£32 | -£0.6 |
| (b) back the named side, match odds | home, 15 min, no stop | 228 | +£6.0 | -£258 | -£2.0 |
| (c) back the under, quiet tenth | 10 min, no stop | 312 | +£5.1 | -£165 | +£2.5 |
(c) is the only one positive on both halves (+£4.8 fit, +£5.1 unseen). But it won on 5 of 7 days, the 90% range is -£2.4 to +£12.1, and a goal costs £61 per £100. Backing the under at every minute instead is £0 (+0.2).

## What is missing, and what each would add
1. **A next-goal market.** We do not record one. It has no time drift: the 22-54p per £1 lost when no goal comes is the cost that kills trade (a). Recording it is the biggest single gain.
2. **More days of plain prices.** Trade (c) and the minutes 45-75 trade need about three times the orders to tell +£5 from £0. The tape grows by itself. **Rerun `gt_analyse.py`, `check_c.py` and `check_band.py` on 29 Nov** (22-28 Nov added). Put either on paper only if its unseen-day 90% range stays above zero.
3. **Faster stats would add little.** The stats we hold arrive 1.5-2.7 min late and added nothing. Only a feed under 30 seconds could change that, and we do not have one.
4. **More matches with a score feed.** Only 31% of matches can be scored today. The prices themselves cannot find every goal: they miss about 30% (a favourite already at 1.01 barely moves).
5. **Bookmaker prices (d).** Test once session 11's table has a week of in-play rows.

How it was checked: goal moments come from the score feed (who scored) timed by the tape (when). Known answers: goal count = final score in 100% of 188 matches (3 and 14 Nov); Over 2.5 result agrees in 99-100%; money logic 12/12 (`test_trade.py`). Limits:
- Bets wait 10 s, as Betfair's in-play delay does.
- After a goal we close on the first *settled* price within 3 minutes, which is kinder than the first wide price.
- Before 10 Nov the match minute is estimated (half-time = kick-off + 47 min).
- A hold that runs past full time is held to the result.
- 24% of goals could not be timed on the tape; the minutes just before them are left out.

Code: /root/pe-sports/goaltrade (gt_build.py, gt_analyse.py, results.md, check_c.py, check_band.py, test_*.py).
