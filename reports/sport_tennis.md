**Recorded now:** Betfair tennis in play: match odds every tick, plus set winner, game-by-game, handicap and totals. **Added today:**
- a live score every 2 s: sets, games, points, server and breaks (tennis.score);
- every Betfair tennis market from 24 h before the start (tennis.bf_pre);
- the result of every tennis market (tennis.result);
- Matchbook tennis, which nobody recorded before (tennis.mb_snap);
- Smarkets tennis before the start (tennis.sm_pre).

All five are in the mechanic's watch list. Data health 09:20 UTC: all collectors up, score feed live on 5 matches.

**Gaps that survive: 0.** £0 a day at £40. Score states measured: 53 cells at set ends, 0 survive (about 0.7 would by luck). The existing map's 8,400 tennis cells (by the clock and by player facts) have 0 beyond chance.

**Put on trial: nothing.** Nothing survived, and the trial's rule format cannot yet express "at the end of a set".

*First version, 27 Nov 2026 09:25 UTC. Final version tonight.*

**What the data does support (leads, not survivors), 31 Oct to 26 Nov, 1,709 matches, real prices on offer, 5 s bet delay:**
- After set 1, the market underrates the player who won it: rated 80.2%, wins 83.4%. Backing every set 1 winner kept £3.60 per £100 over 1,539 bets (about £71 a day). But all of it came in the first half of the dates (+£1,951, then −£31), so it fails.
- The steadiest version: back the set 1 winner who was also favourite at the start. That kept £2.40 per £100 on 1,050 bets, positive in both halves (+£397 / +£499), +£696 without its best day, about £33 a day. It fails the period test (+3.1 / −0.4 / +4.8 points). **NOT YET: re-test on Thu 4 Dec with a week more data and exact set-end times from the score feed.**
- At one set all, the player who won set 1 but lost set 2 is underrated: rated 48.2%, wins 52.2%. Backing them kept £7.70 per £100 on 503 bets, but the second half lost £22, so it fails too.
- "Back the player who lost the first set", the known trader idea, loses £24 per £100. Killed.
- A trade looked very good on stream prices: at one set all, back the player who just won set 2 and green up within 10 minutes, +£12 per £100. The polled in-play prices are an independent record of the same market, and on them it loses £5–6 per £100. **Not trusted.** A live check of the stream's book against Betfair's own book is running until 12:20 UTC.

**Score feed:** found and recording. It is Betfair's own in-play scores service, the one betfair.com shows next to the prices: no login, no purchase. Betfair's official scores service refuses our app key ("needs access granted"), so it is not used. The terms page is behind a Cloudflare check and could not be read. **Peter decides whether the website service may be used.** On 5 morning matches the feed's points line up best with the price moves at about 1 s behind, but with only 5 matches that is weak. Re-measured tonight on the afternoon's matches.

**Rule 708, checked:**
- The opposite side (laying): laying the set 1 winner loses £5.70 per £100. Laying the set 1 loser at under 5.0 makes £13 per £100, but fails the second half (−£700).
- The next set's winner market: backing the set 1 winner to win set 2 too makes £2 per £100, but fails the second half.
- Smarkets: in-play tennis has a price on 25 of 260 players a day, so there is almost nothing to take.
- Not recorded, so not tried: Matchbook before today, and set betting, handicaps and totals at set ends (about 5 matches a day since 21 Nov).

**Could not be measured, and the one thing missing for each:**
- Break point, set point, serving or receiving, after a break: the score feed only started today. Missing: about 3 weeks of feed days.
- Ranking gap and surface: the results file stops on 25 Sep 2026. Missing: a current rankings list.
- Best of 5: there were no best-of-5 matches in these weeks. Missing: the Australian Open in January.
- Real prices before the start: never recorded until today. Missing: days.
