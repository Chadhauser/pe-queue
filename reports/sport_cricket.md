**Recorded:** Betfair cricket match odds (ip_tape every 32 s since 14 Nov; an older favourite-only tape 26 Oct - 9 Nov) and side markets once a minute (extra_snap, since 21 Nov). **Added today** (one recorder plus a daily job, both in the mechanic's watch list): the live score ball by ball from Betfair's own scores service, and the ESPN score panel restarted; every Betfair cricket market (163 on 20 events today, about 20 types) in play every 2-10 s, before the start, and settled; Matchbook and Smarkets cricket, never recorded before; our own form rating, rebuilt daily.

**Gaps that survive: 0.** £0 a day at £40.

**Put on trial: nothing.** The trial list (grid.trial_rules) is unchanged.

*Final version, 27 Nov 2026 13:30 UTC. Real prices on offer, money shown at least £2, stake up to £40, lays only below 5.0 and at most £50 to lose, 2% commission, the next quote at least 5 s after the event (with 32 s polling that is about 32 s: pessimistic). 452 settled match-odds markets in play, 14-27 Nov; 10-13 Nov nothing was recorded.*

**Why the feed stopped:** the old table (cricket_matches_today) was filled from ESPN's public score panel by the Edge Letter pipeline, which does not run on this server. It last ran on 21 Oct at 09:00, and nothing here could restart it. It is restarted today, beside Betfair's own scores service. Betfair's service covers only the main events (1 of 6 live at noon); ESPN covers A-team, domestic and women's matches. **Delay:** on 20 wickets, both feeds were behind the price every time: Betfair's service by a median of 78 s, ESPN by 62 s. So the feeds tell us the score. They cannot beat the price.

**What the data supports (leads, NOT YET survivors). Next test Thu 4 Dec, with a week of 2-second prices:**
- A favourite rated 70-90% in play wins more often than the price says: rated 75% it won 80%, rated 85% it won 89%, over about 640 moments. At the price on offer it kept about £2 per £100, but only in the second half of the dates. History agrees: across 3,800 matches in 2025-26, short favourites won 3-5 points more often than priced, in both periods.
- "N runs or more" markets in play: steps rated 80-95% likely were reached only 67-71% of the time. But that is only 15 markets, and laying those steps lost money in the second half.
- After a big swing in match odds, about half the innings-runs and over lines still showed the same price 30-60 s later, with about £12,000 on offer at those prices. Whether taking them pays needs those markets settled, from the score we now record.

**Wickets and big overs** (a fall of 6 points or more in one quote: 1,490 cases in 205 matches): the price neither over- nor under-reacts. Backing the side just hurt won 44% of the time when priced at 44%. Every trading version (out at +5, 10 or 20%; stop at 10, 25 or 50%; time limit 5, 15 or 30 min) lost £11-20 per £100, because the gap between back and lay in thin in-play cricket is wider than the swing back. Powerplay overs were no different: rated 44%, won 45%.

**Small markets:** most recorded cricket is small: the Syed Mushtaq Ali Trophy (110 matches), women's, T10, Nepal, Hong Kong.
- Markets with £1-5k matched: the in-play favourite rated 69% won 83%. Backing it at the start of play kept £25 per £100, positive in both halves, but on only 23 bets.
- In history, the quietest quarter of markets is priced no worse at the start than the busiest.
- Smarkets and Matchbook against Betfair at the same moment: 3 real crossings in 90 minutes, worth £20 of money shown in total. Pennies.
- The "Match Odds (Inc. Tie)" market only looks out of line with match odds: in it a tie loses team bets, while in plain match odds a tie is void.

**Form guide:** a rating for every team built from Betfair results since Oct 2025 (4,045 matches). It updates after every match and weighs the strength of the other side, how safe the win was in play, format, home side and how recent the match was, plus who keeps beating their price. Fitted before 1 Mar 2026 and tested on 2,516 later matches it never saw, it predicts far worse than the price (log loss 0.69, against 0.60 for the market and 0.69 for a coin). Where form and price disagree by 10-30 points, the market's chance was right to within 2 points. Above 30 points the market was right and form's long shots did even worse (priced at 13%, won 8%). At real prices on our recorded days, form's side lost £15 per £100 on 101 bets. A team's record of beating its price, or of coming back from below 30% in play, does not carry into its next match.

**Known rules, run inside every format, money band and women/men** (50 combinations; luck alone would make roughly 7-12 look positive in both halves; 3 did, with 23-32 bets each):
- Lay the favourite in play: −£13 per £100 overall. In T10 it was +£26 on 25 bets, but history says T10 favourites win more than priced.
- The old paper rule "lay at the start price and green up at +20%": −£18 per £100.
- The old rule "back the favourite once it drifts to 1.5x its start price": −£21. Its opposite side: +£5, but negative in the second half.

**Rule 708:** opposite sides were all tried (fade and follow, back and lay the favourite, favourite and outsider, form's side and the market's side). Other markets: tied match, toss, the runs ladders and top batter were tried (above). Other exchanges: from today only.

**Could not be measured, and the ONE thing missing for each:**
- Who batted second (the chase rules from the old rule library): no match we hold has both a price and the toss. Recorded from today.
- Over/under innings runs and over lines: their results need the final score. Recorded from today.
- State in play (runs, wickets in hand, required rate, who is batting) against the price: only today has scores.
- Stale offers after a wicket, second by second: only today has 2-second prices.
- Smarkets against Betfair at the same moment: Smarkets rows before 13:25 today carry a time up to 3 min out (fixed).

**Peter:** the ESPN panel and Betfair's scores service need no login and no payment, but I could not confirm their terms allow automated reading. Whether we keep using them is your call. Separately, /root/trading/cricket_results.py has passwords written into the file and fails to log in; I did not touch it.
