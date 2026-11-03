# Finder 2026-11-03 — item 9: other sports on ip_tape

**Job:** jobs/458_other_sports_iptape.sh. Run 1 was OOM-killed after the census, while loading basketball COMBINED_TOTAL (7.7M rows). Run 2 (the one allowed fix) restricts the tests to winner markets (MATCH_ODDS / MONEY_LINE / RT_MATCH_ODDS) and excludes horse racing, which the item doesn't list and racing_bsp covers. Run 2 was clean.

## Census (ip_tape, all non-tennis, non-football; **28 Oct → 3 Nov only, ~6 days**)
| sport | markets (all types) | winner market | markets | note |
|---|---|---|---|---|
| horse_racing | 1,701 | WIN | 1,443 | excluded (out of scope) |
| basketball | 800 | MATCH_ODDS | 422 | **only one ≥150**: 330 inferable, median 232 in-play snapshots |
| ice_hockey | 172 | MONEY_LINE | 106 | < 150 |
| american_football | 135 | MATCH_ODDS | 67 | < 150 |
| cricket | 124 | MATCH_ODDS | 101 | < 150 |
| darts | 88 | MATCH_ODDS | 87 | < 150 |
| esports / snooker / rugby union | 50 / 46 / 40 | MATCH_ODDS | 36 / 46 / 23 | < 150 |
| AFL, rugby league, MMA, golf, baseball, boxing, volleyball, motor | ≤ 16 each | | | < 150 (baseball 5 MO) |
Basketball HANDICAP (216) and COMBINED_TOTAL (160) are multi-line markets with no single-runner result, so they weren't tested. "Inferable" = exactly one runner at back/ltp ≤1.05 on the last OPEN in-play snapshot.

## Tests (basketball MATCH_ODDS, 422 markets; halves split at 2026-10-31 11:35)
Real touch +1 tick each side, 2% commission, held to the result. Unknown result: *known* = dropped (diagnostic only, never eligible); *worst* = −£10.
| line | n | markets | per £10 | t | h1 | h2 |
|---|---|---|---|---|---|---|
| grid back, all points (known) | 2,167 | 329 | −1.81 | −6.9 | −2.21 | −1.37 |
| grid back (worst) | 2,880 | 421 | −3.84 | −18.4 | −3.82 | −3.85 |
| grid lay (known) | 2,223 | 329 | −0.97 | −1.9 | −2.26 | +0.35 |
| grid lay (worst) | 2,848 | 420 | −2.95 | −7.4 | −3.62 | −2.34 |
| momentum back (≥15% shorter over 20 snapshots, exit +20) (known) | 545 | 345 | −2.24 | −14.8 | −1.92 | −2.57 |
| momentum back (worst) | 551 | 349 | −2.33 | −15.2 | −2.01 | −2.65 |

Top cells by t (168 cells, 40 at n≥300). **None passes:**
| cell | n | per £10 | t | h1 | h2 |
|---|---|---|---|---|---|
| lay at 25% / <1.5 (worst) | 216 | +1.48 | 0.43 | −3.14 | +6.10 |
| lay first / 1.5-2 (known, diag.) | 126 | +1.97 | 1.87 | +0.90 | +3.11 |
| back first / 2-3 (known, diag.) | 121 | +1.97 | 1.82 | +0.98 | +2.92 |
| lay at 25% / <1.5 (known, diag.) | 176 | +4.09 | 0.97 | −2.04 | +10.96 |
| lay first / <1.5 (worst) | 203 | −1.35 | −0.78 | −3.56 | +0.93 |
| back first / 2-3 (worst) | 161 | −1.00 | −1.10 | −1.00 | −1.00 |
| all other cells | | ≤ +0.55 | ≤ 0.66 | | |

## Verdict
**Nothing passes.** Only basketball MATCH_ODDS clears the 150-inferable-market bar: 22% of its markets have no inferable result and none of its cells reach t 2. Momentum loses £2.3 per £10, roughly the round-trip spread plus two ticks. Every other sport is below 150 markets in the 6 days ip_tape holds. Re-test darts, ice hockey and cricket once ip_tape has ~3–4 more weeks.
