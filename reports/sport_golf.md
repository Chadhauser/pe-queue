**Recorded now (added today, 27 Nov):** every Betfair golf market (winner, top 5/10/20, each way, three-balls, two-balls, match bets, specials) for the whole tournament, every 2-15 min with the money shown, plus Betfair's own results; Smarkets and Matchbook golf (never recorded before); the ESPN leaderboard every 10 min in play with tee times; ESPN results back to 2020 (PGA, DP World, LPGA, LIV, Korn Ferry, Champions) for the form guide. Before today golf was only 15-minute Betfair quotes from 24 Sep to 22 Oct, and those stopped two hours after each first tee.
**Gaps that survive:** 0 beyond chance (10 cells pass against 8 expected by luck; all are long shots winning less often than rated, which can only be used by laying at 50.0 or longer). One lead holds at real prices in both halves: about £13 a day at the stakes on offer (£16 at £40).
**On trial:** G1, the match-bet favourite, frozen 27 Nov on the golf paper trial (golf.trial_rules, settled daily by golf_trial.py). It is not in grid.trial_rules, because trial.py would send it into the stream test, which has no golf.

*First version, 27 Nov 2026 12:05 UTC. Form guide and the round-by-round in-running parts follow in the final version today.*

**What survives, in plain English**
- G1: in a golf tournament match bet (two named players, who finishes ahead), back the one the market rates the more likely, in the hour before the start, and hold it. On the recorded days the favourite was rated to win 62% of the time and won 77%. Taking the price actually on offer (average 1.59, average stake £32, capped at the money shown) kept +£17.3 per £100 on 62 bets over 7 tournaments: first half +17.0, second half +17.7, worst tournament -£35, still +£223 without the best tournament. It held at every moment measured: 30 to 6 hours before (+11.8), 6 to 1 hour before (+8.6) and the last hour (+17.3). Not proven: 62 bets cannot rule out luck (about 1 in 12). That is why it is on paper, not money.

**Small markets**
- Golf's side markets are tiny: three-balls a median £17 matched the day before and £124 in the last hour; match bets £300-400; top 5/10/20 £20-40k; winner £200k+.
- Three-ball favourites with under £100 matched won 50% against 42% rated (+15.9 per £100 in the last hour), but the first half lost (-19.5) and the second won (+49.2), so it is not on trial. With £100-1,000 matched the favourites lost (-22).
- Side market against main market at the same moment: where a player's top-5/10/20 price disagrees with what his winner price implies, the results follow the side market, not the winner market. Nobody is leaving those prices behind.
- Taking prices in the outright markets costs a lot: backing at the best price shown lost 25-99 per £100 in almost every price band, because the gap between back and lay on players outside the top few is very wide. The money in golf outrights, if any, is in offering prices, not taking them. Our 15-minute quotes cannot show fills; today's recorder keeps 2 levels of prices and each player's money matched, which is the start of that test.

**What could not be measured, and the one thing missing for each**
- Back before the tournament, trade out after round 1 or 2: the old recordings stop 2 hours into round 1. Missing: prices through all four days, which the recorder takes from today (first usable tournament: the Hero World Challenge, 3-6 Dec).
- In running by leaderboard position and strokes behind: round-by-round standings are exact from the ESPN scores, but there are no prices after round 1 to set them against. Missing: the same four-day prices.
- The 2020-2026 Betfair golf history table: unusable. Its "last traded" is the price after the result (winners at 1.01), and its three-ball ids merge about ten groups each. Missing: the Betfair Historic Data golf files, which need a fresh historic-data login (the stored one returns 401). Only Peter can renew it.
- Make the cut, round leader, hole-in-one: not offered in anything we recorded. Recording from today.
- Each way: a win-and-place market that cannot be read as one chance. Left out of the map.
- Smarkets and Matchbook: recorded from today only (5 Smarkets golf events, 3 Matchbook markets live today).
- Weather: not joined yet (free source not chosen).
