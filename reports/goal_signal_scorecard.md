# Goal signal against real games (2026-11-23) - tier one, money £0 (scorecard only, no bets, no paper)

**On 501 matches over 3 days, when the signal said HIGH a goal followed within 10 minutes 23% of the time, against 21% normally for those same minutes and scores; when it said LOW, 14% (normally 19%).**
Is that enough to trust? Not yet. Resampling whole matches, HIGH could plausibly be anywhere from 20% to 25% and LOW from 13% to 16%. The HIGH range still includes the normal rate, so this could be luck. LOW is below normal even at the top of its range. Each extra day narrows it; a week of nights (the table below fills itself) should roughly halve the range.

_Data: 102 matches kicked off and finished on the stream; 65 had a score feed; 63 could be scored (63 live by v2, 0 replayed on the recorded ticks; the scorecard uses the in-play minutes of these). v2 has run live since 21 Nov 17:18 UTC: every match that kicked off before then is replayed, every later one is its live record (list: goaltrade/cache/sc_match_*.parquet, column live); replay and live agree to a median 0.3 points where both exist. Goals in those matches: 162 on the score feeds; 152 (94%) matched to a Betfair suspension, the feeds a median 1.3 min behind it; 10 did not match (timed from the feed less 1.5 min). The other way round, 110 suspensions with a 10% price move had no goal on any feed: penalties awarded, red cards, VAR, goals ruled out, or a price measured on a thin outsider - so they are counted, not used._

## Scorecard: every call

Each call is one minute of one match. "Normal" = the average for the same minutes and scores. Range = 95% by resampling matches.

| signal says | calls | matches | goal within 10 min | normal | share of playing time |
|---|---|---|---|---|---|
| v2 HIGH | 1,548 | 62 | **15%** (10%-19%) | 16% | 26% |
| v2 NORMAL | 3,022 | 63 | **26%** (22%-30%) | 23% | 50% |
| v2 LOW | 1,464 | 62 | **10%** (7%-14%) | 16% | 24% |
| old HIGH | 4 | 1 | **0%** (-) | 21% | 0% |
| old NORMAL | 3,620 | 45 | **23%** (19%-28%) | 22% | 100% |
| old LOW | 0 | 0 | - | - | - |

v2's actual alerts (chance 29% or more, nothing gated, one per match per 10 min): 65 on 33 matches, a goal followed within 10 min 29% against 21% normally.
The old signal gave a number on 45 of 63 matches; it said exactly 38% (its fixed default) on 88% of those minutes. Its only alerts were 5 half-time bets on the final total (e.g. "back Under 3.5"), not goal-timing calls; 2 could be linked to a scored match and 2 of them (100%) were right.

- **Goals and what v2 was saying just before:** of 147 goals it was watching, 32 (22%) came while it said HIGH, 90 (61%) NORMAL, 25 (17%) LOW; it spent 26% / 50% / 24% of playing time in each. (17 more goals came with no v2 call in the 3 min before: no feed, half time or gated.)
- **Warning:** 62 goals had a HIGH in the 10 minutes before; the HIGH had been on for 8.9 min on average (median 5.5).
- **HIGH with no goal:** 247 of 321 HIGH spells (77%) passed with no goal in the 10 minutes after.

**By half, score and late on (v2): goal within 10 min when it said HIGH / NORMAL / LOW, with the plain average for those minutes)**

| | HIGH | NORMAL | LOW |
|---|---|---|---|
| first half | 13% of 783 (avg 14%) | 27% of 1,514 (avg 24%) | 19% of 377 (avg 26%) |
| second half | 17% of 765 (avg 17%) | 26% of 1,508 (avg 22%) | 8% of 1,087 (avg 13%) |
| level | 14% of 848 (avg 17%) | 28% of 1,508 (avg 24%) | 8% of 361 (avg 21%) |
| one-goal game | 18% of 276 (avg 14%) | 27% of 1,156 (avg 25%) | 11% of 701 (avg 16%) |
| two or more apart | 14% of 424 (avg 14%) | 15% of 358 (avg 12%) | 11% of 402 (avg 13%) |
| last 15 min (75+) | 18% of 214 (avg 10%) | 23% of 390 (avg 13%) | 6% of 916 (avg 11%) |

## What would make it sharper (from 21-22 Nov; written once by session 22, not rewritten nightly)

Looked at the 661 goals v2 called NORMAL or LOW just before, and the 5,882 HIGH minutes with no goal, against the facts and prices known at that minute (sc_diag.py).

1. **Its HIGH only works in the second half; in the first half it is noise.** Second half: 28% against 23% normal (3,428 calls); last 15 minutes: 30% against 16% (949). First half: 19% against 20% (4,223 calls), which is more than half of all its HIGH calls. **Try:** a separate first-half cut-off, or no HIGH before minute 45. Session 13 tested the first half as an input, not as its own cut-off.
2. **The match facts we hold would not have caught the missed goals.** A shot on target in the last 5 minutes: 100 of 297 missed-goal minutes (34%) against 3,363 of 9,914 quiet minutes (34%), so no difference. Two or more corners: 11% against 10%. These stats exist on only 52% of minutes. Red cards are known on only 4% of minutes (19 goals), too few to test. No feed records substitutions. A team chasing late (one-goal game from minute 70) scored **less** often when v2 said NORMAL/LOW (13.5% against 17.6% normal, 2,813 calls). **Try:** nothing from these feeds yet. A substitutions feed would be the one new fact worth adding.
3. **The over price not drifting is the only thing that lifted the missed goals.** On NORMAL/LOW minutes where the over price was drifting slower than normal over 5 minutes, a goal followed 24.4% of the time against 22.5% normal (4,056 calls, 363 matches): +2 points. It is already an input, but only up to 5 minutes. **Try:** the same measure over 10-15 minutes, with more weight late in the second half where finding 1 says the signal works.

## Day by day (rewritten 23:30 UK each night)

**Second version against the current one: 3 of 7 days, too early to call. LOW (points below normal): current +3.3 (10,556 calls), second +3.0 (10,617), difference -0.3 (range -0.6 to +0.1); late HIGH (points above normal): current +12.8 (1,394 calls), second +12.6 (1,385), difference -0.1 (range -1.4 to +1.0).**

Second version = fitted on days before 21 Nov; no HIGH before the second half (so its HIGH is second half only); the over price not drifting measured over 5, 10 and 15 minutes, weighted more late on. Scored from the recorded ticks on the same calls; late HIGH = HIGH from minute 75, goal within 10 (calls).

| date | matches | calls | HIGH: goal within 10 | NORMAL | LOW | late HIGH | 2nd version HIGH | 2nd NORMAL | 2nd LOW | 2nd late HIGH | all minutes |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-11-21 | 264 | 23,197 | 23% (5,562) | 23% | 15% (5,807) | 31% (699) | 27% (2,555) | 23% | 16% (5,587) | 30% (706) | 21% |
| 2026-11-22 | 174 | 16,614 | 25% (3,766) | 25% | 14% (4,638) | 29% (481) | 30% (1,829) | 24% | 17% (3,840) | 30% (468) | 22% |
| 2026-11-23 | 63 | 6,034 | 15% (1,548) | 26% | 10% (1,464) | 18% (214) | 18% (779) | 23% | 13% (1,190) | 18% (211) | 19% |

## Three matches, five minutes at a time

v2 = version 2's chance of a goal in the next 10 minutes; usual rate = how often a goal followed in the same minute band and score on 2-19 Nov (what HIGH / LOW is measured against); old signal = the old model's chance and its band against its own usual level. RIGHT/WRONG marks only HIGH and LOW.

### Most money matched on 2026-11-23 with full data (£1,524,254 on match odds): Levante v Elche (live)
Goals (Betfair suspension times): 62' 0-1, 89' 1-1. On these lines: 4 right, 10 wrong.

| min | score | v2: goal in next 10 min | usual rate | old signal | next 10 min | call |
|---|---|---|---|---|---|---|
| 2 | 0-0 | 12% **LOW** | 20% | 40% NORMAL | no goal | RIGHT |
| 5 | 0-0 | 21% **NORMAL** | 20% | 41% NORMAL | no goal |  |
| 10 | 0-0 | 24% **NORMAL** | 20% | 41% NORMAL | no goal |  |
| 15 | 0-0 | 24% **NORMAL** | 20% | 41% NORMAL | no goal |  |
| 20 | 0-0 | 25% **HIGH** | 18% | 41% NORMAL | no goal | WRONG |
| 25 | 0-0 | 25% **HIGH** | 18% | 41% NORMAL | no goal | WRONG |
| 30 | 0-0 | 26% **HIGH** | 18% | 41% NORMAL | no goal | WRONG |
| 36 | 0-0 | 25% **HIGH** | 15% | 41% NORMAL | no goal | WRONG |
| 40 | 0-0 | 26% **HIGH** | 15% | 41% NORMAL | no goal | WRONG |
| HT | | | | | | |
| 46 | 0-0 | 28% **HIGH** | 21% | 38% NORMAL | no goal | WRONG |
| 50 | 0-0 | 28% **HIGH** | 21% | 41% NORMAL | no goal | WRONG |
| 55 | 0-0 | 27% **NORMAL** | 21% | 41% NORMAL | GOAL 62' (0-1) |  |
| 60 | 0-0 | 30% **HIGH** | 21% | 41% NORMAL | GOAL 62' (0-1) | RIGHT |
| 66 | 0-1 | 24% **NORMAL** | 22% | 41% NORMAL | no goal |  |
| 70 | 0-1 | 30% **HIGH** | 22% | 41% NORMAL | no goal | WRONG |
| 76 | 0-1 | 33% **HIGH** | 20% | 41% NORMAL | no goal | WRONG |
| 80 | 0-1 | 30% **HIGH** | 20% | 41% NORMAL | GOAL 89' (1-1) | RIGHT |
| 85 | 0-1 | 33% **HIGH** | 20% | 45% NORMAL | GOAL 89' (1-1) | RIGHT |
| 90 | 1-1 | 41% **HIGH** | 29% | none | no goal | WRONG |

### Best called on 2026-11-23 (99% of 99 HIGH/LOW calls right): Diriangen FC v Managua FC (live)
Goals (Betfair suspension times): 5' 0-1. On these lines: 18 right, 1 wrong.

| min | score | v2: goal in next 10 min | usual rate | old signal | next 10 min | call |
|---|---|---|---|---|---|---|
| 2 | 0-0 | 8% **LOW** | 20% | 38% NORMAL | GOAL 5' (0-1) | WRONG |
| 5 | 0-1 | 12% **LOW** | 21% | 38% NORMAL | no goal | RIGHT |
| 10 | 0-0 | 6% **LOW** | 20% | 38% NORMAL | no goal | RIGHT |
| 16 | 0-0 | 6% **LOW** | 18% | 38% NORMAL | no goal | RIGHT |
| 20 | 0-0 | 6% **LOW** | 18% | 38% NORMAL | no goal | RIGHT |
| 25 | 0-0 | 16% **NORMAL** | 18% | 38% NORMAL | no goal |  |
| 30 | 0-1 | 17% **LOW** | 25% | 38% NORMAL | no goal | RIGHT |
| 36 | 0-1 | 13% **LOW** | 24% | 38% NORMAL | no goal | RIGHT |
| 40 | 0-1 | 8% **LOW** | 24% | 38% NORMAL | no goal | RIGHT |
| 45 | 0-1 | 8% **LOW** | 24% | 38% NORMAL | no goal | RIGHT |
| HT | | | | | | |
| 46 | 0-1 | 11% **LOW** | 24% | 38% NORMAL | no goal | RIGHT |
| 50 | 0-1 | 11% **LOW** | 24% | 38% NORMAL | no goal | RIGHT |
| 55 | 0-1 | 15% **LOW** | 24% | 38% NORMAL | no goal | RIGHT |
| 61 | 0-1 | 10% **LOW** | 22% | 38% NORMAL | no goal | RIGHT |
| 65 | 0-1 | 10% **LOW** | 22% | 38% NORMAL | no goal | RIGHT |
| 70 | 0-1 | 9% **LOW** | 22% | 38% NORMAL | no goal | RIGHT |
| 75 | 0-1 | 10% **LOW** | 22% | 38% NORMAL | no goal | RIGHT |
| 80 | 0-1 | 9% **LOW** | 20% | 38% NORMAL | no goal | RIGHT |
| 85 | 0-1 | 14% **LOW** | 20% | 38% NORMAL | no goal | RIGHT |
| 90 | 0-1 | 10% **LOW** | 20% | none | no goal | RIGHT |

### Worst called on 2026-11-23 (0% of 42 HIGH/LOW calls right): Jong PSV Eindhoven v Jong FC Utrecht (live)
Goals (Betfair suspension times): 18' 1-0, 31' 1-1. On these lines: 0 right, 3 wrong.

| min | score | v2: goal in next 10 min | usual rate | old signal | next 10 min | call |
|---|---|---|---|---|---|---|
| 20 | 1-0 | 22% **NORMAL** | 25% | none | GOAL 31' (1-1) |  |
| 26 | 1-0 | 24% **NORMAL** | 25% | none | GOAL 31' (1-1) |  |
| 31 | 1-1 | 25% **HIGH** | 15% | none | no goal | WRONG |
| 35 | 1-1 | 23% **HIGH** | 15% | none | no goal | WRONG |
| 41 | 1-1 | 24% **HIGH** | 15% | none | no goal | WRONG |
| HT | | | | | | |

_Built 2026-11-24 07:34 UTC by /root/pe-sports/goaltrade/sc_build.py + sc_report.py (session 22). Scorecard only._
