**Recorded:** Betfair tennis in play: match odds every tick, plus set winner, set betting, game-by-game, handicaps and totals. **Added today**, all in the mechanic's watch list:
- a live score every 2 s: sets, games, points, server and breaks (tennis.score; 19 matches and 5,287 score changes by 11:30 UTC);
- every Betfair tennis market from 24 h before the start (464 markets on 71 events today);
- the result of every tennis market;
- Matchbook tennis, never recorded before;
- Smarkets tennis before the start.

Data health 11:30 UTC: all collectors up.

**Gaps that survive: 0.** £0 a day at £40. Set-end states: 53 cells, 0 survive (about 0.7 would by luck). Clock and player facts were already in the map: 8,400 tennis cells, 0 beyond chance.

**Put on trial: nothing.**

*Final version, 27 Nov 2026 11:40 UTC. Real prices on offer, 5 s bet delay, 2% commission, stake capped at the money shown, lays capped at £50 loss. 1,711 matches from 31 Oct to 26 Nov.*

**What the data supports (leads, NOT YET survivors):**
- After set 1, the market underrates the set 1 winner: rated 80.2%, wins 83.4%. Backing all of them kept £3.60 per £100 on 1,539 bets, but it was all in the first half of the dates (+£1,951, then −£31).
- The steadiest version: back the set 1 winner who was also favourite at the start. That kept £2.40 per £100 on 1,050 bets, positive in both halves (+£397 / +£499), +£696 without its best day, about £33 a day. It fails the middle period (−0.4 points). **Next test Thu 4 Dec**, with a week more data and exact set-end times from the score feed.
- At one set all, backing the player who won set 1 but lost set 2: +£7.70 per £100 on 503 bets, but the second half was −£22.
- "Back the player who lost the first set", the known trader idea: −£24 per £100. **Killed.**
- Trading the one-set-all swing (back the player who just levelled, green up within 10 minutes): +£10 per £100 on 523 trades. But its newest period lost (−£3.20 per £100), its t-statistic is only 1.9, and that's the best of 12 versions tried. Not a survivor.

**Score feed:** Betfair's own in-play scores service, the one betfair.com uses: no login, no purchase. Betfair's official scores service refuses our app key, so it is not used. **Peter: the terms page sits behind a Cloudflare check and could not be read, so whether we may keep using this service is your call.**
- **Delay:** across 18 matches and 3,440 points, the price moves first 70% of the time. The feed's points line up best with the price at about 1 s behind, but that signal is weak. Taking the biggest nearby price jump instead, the feed is a median 7 s behind. So the feed tells us the score; it does not beat the price.
- **Rebuilding the score from the price alone** is unreliable against the feed as truth (167 breaks in 551 games): at most 25% of big 60-second moves are breaks, and it finds 12–53% of breaks depending on the threshold. So score states before today cannot be rebuilt from the price.

**Checks behind the numbers:**
- The stream's prices equal Betfair's own book 99.9% of the time (24,284 live comparisons).
- The polled recorders (ip_tape, extra_snap, book_snap) leave out Betfair's cross-matched prices, so their spreads look wider than the real book. Any real-price result from them is pessimistic. That affects other sessions too.

**Rule 708:**
- Opposite side: laying the set 1 winner loses £5.70 per £100. Laying the set 1 loser (under 5.0) makes £13 per £100 but loses in the second half.
- Next set's winner market: +£2 per £100, but loses in the second half.
- Smarkets: almost no in-play tennis prices (25 of 260 players had any price on 22 Nov).
- Not tried because not recorded: Matchbook before today, and handicaps, totals and set betting at set ends (about 5 matches a day).

**Could not be measured, and the one thing missing for each:**
- Break point, deuce, serving or receiving, after a break: there is a first read on 11 matches, for example a server at break point rated 35% who won 32%. Missing: about 3 weeks of feed days.
- Ranking gap and surface: missing a current rankings list (ours stops on 25 Sep).
- Best of 5: missing the Australian Open in January.
- Real prices before the start: missing days (recorded from today).
