# Finder 2026-11-03 — item 0g: VAR snap-back and goal overshoot (jobs/468)

**Data.** goal_timeline (live score feed, real `captured_at`, median cadence 74 s, p90 113 s) joined to liq_sample (real Betfair touch,
29 Oct 03:33 – 3 Nov 20:48 UTC) by event-name token match, same London day (jobs/300 style). 1,292 recorder games, 1,175 mapped to
the feed; 25 dropped for the MO label defect found in 0e (two runners labelled AWAY). Both clocks are real timestamps, so no minute alignment.

**Rules.** Entry = first recorder sample <= 90 s after the signal; exit = first sample >= entry + hold (never forward-filled). If there
is no later print, MO settles at the result and OU25 settles at the result if the line is passed. One tick adverse on entry and exit,
2% commission on profit, £10 risk. Halves split at 2026-11-01. P&L unit asserts pass (known answers in the job).

**Feed events.** 8,817 score rises. 330 reversals (one side falls back by exactly 1 within 15 min and the next row agrees). 313 other
falls (glitches, e.g. a jump to 0-0, not traded). 207 reversals are in mapped games and 186 have a pre-goal MO price. Of those, 3 are
SWAPs (the other side scores within 180 s of the revert) and 183 are VAR-type.

**Snap-back (VAR-type, n 183).** For the side the feed wrongly credited, median MO back price: **1.54 pre-goal, 1.68 at the flash,
2.80 at the feed revert**. That is the wrong direction for a disallowed goal: the market never priced these as goals for that side.
144 moved > 15% at some point. Only 24 came back within 5% of the pre-goal price (median 70 s after the revert, 21% of them before it).
**Reading: most feed "reversals" are feed errors (wrong side or phantom goal) while the real game moves on, not VAR events the market
overreacted to.** Any bot that triggers on a goal_timeline goal without checking the market has moved is exposed to these errors:
330 reversals in 6 days (3.7% of feed goals), 183 of them confirmed against the market (2.1%).
Caveats: entries <= 90 s after a feed goal may sit on a just-reopened book; OU25 settlement uses the feed score (phantom goals included).

| line | hold | n | games | per £10 | t | h1 | h2 | pass |
|---|---|---|---|---|---|---|---|---|
| R_LAY_SCORER_VAR (lay wrongly-credited side at revert) | 3 m | 163 | 139 | −0.29 | −0.32 | +0.65 | −1.32 | no |
| R_LAY_O25_VAR | 3 m | 122 | 105 | −0.67 | −3.60 | −0.75 | −0.57 | no |
| R_BACK_OTHER_VAR (back the side marked down) | 3 m | 158 | 134 | −2.06 | −6.28 | −1.96 | −2.17 | no |
| R_*_SWAP | 3 m | 2 | 2 | (+7.30 / +4.27) | — | — | — | n 2 |
| G_BACK_SCORER (standing goal) | 10 m | 2,253 | 969 | −0.89 | −7.0 | −0.95 | −0.84 | no |
| G_BACK_SCORER | 5 m | 2,253 | 969 | −1.05 | −11.6 | −1.07 | −1.03 | no |
| G_BACK_SCORER | 3 m | 2,253 | 969 | −1.11 | −15.6 | −1.14 | −1.08 | no |
| G_LAY_SCORER (overshoot fade) | 10 m | 2,451 | 987 | −2.25 | −16.8 | −2.18 | −2.33 | no |
| G_LAY_SCORER | 5 m | 2,451 | 987 | −2.12 | −20.3 | −2.02 | −2.23 | no |
| G_LAY_SCORER | 3 m | 2,451 | 987 | −2.07 | −23.4 | −2.12 | −2.03 | no |

Correlation: up to 3 G entries per goal (holds share the entry) and several goals per game, so t is overstated; that cannot rescue negative
means. Back and lay on the same goal are both negative: the post-goal spread costs more than any drift.

**Verdict: nothing passes.** No VAR line (n < 300 and negative). Goal overshoot/continuation loses £0.9–£2.3 per £10 both ways, both halves.

**Side finding to act on (not a line).** About 2% of feed goals are reversed while the market moves the *other* way. Suggested guard for any
goal_timeline-driven bot: require the credited side's MO price to shorten >= 15% within 2 min of the feed goal before acting.
Tick note: tick(2.00) returns 0.02 both ways, so a down-tick from exactly 2.00 is charged 0.02 rather than 0.01 (conservative, also in 462).
