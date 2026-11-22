# Goal signal against real games (2026-11-21, 2026-11-22) - tier one, money £0 (scorecard only, no bets, no paper)

**On 370 matches over 2 days, when the signal said HIGH a goal followed within 10 minutes 23% of the time, against 21% normally for those same minutes and scores; when it said LOW, 15% (normally 19%).**
Is that enough to trust? Not yet. Resampling whole matches, HIGH could plausibly be anywhere from 21% to 25% and LOW from 13% to 17%. The HIGH range still includes the normal rate, so this could be luck. LOW is below normal even at the top of its range. Each extra day narrows it; a week of nights (the table below fills itself) should roughly halve the range.

_Data: 542 matches kicked off and finished on the stream; 404 had a score feed; 378 could be scored (160 live by v2, 218 replayed on the recorded ticks; the scorecard uses the in-play minutes of these). v2 has run live since 21 Nov 17:18 UTC: every match that kicked off before then is replayed, every later one is its live record (list: goaltrade/cache/sc_match_*.parquet, column live); replay and live agree to a median 0.3 points where both exist. Goals in those matches: 1004 on the score feeds; 883 (88%) matched to a Betfair suspension, the feeds a median 1.5 min behind it; 121 did not match (timed from the feed less 1.5 min). The other way round, 590 suspensions with a 10% price move had no goal on any feed: penalties awarded, red cards, VAR, goals ruled out, or a price measured on a thin outsider - so they are counted, not used._

## Scorecard: every call

Each call is one minute of one match. "Normal" = the average for the same minutes and scores. Range = 95% by resampling matches.

| signal says | calls | matches | goal within 10 min | normal | share of playing time |
|---|---|---|---|---|---|
| v2 HIGH | 7,651 | 343 | **23%** (21%-25%) | 21% | 23% |
| v2 NORMAL | 16,967 | 370 | **24%** (22%-26%) | 22% | 51% |
| v2 LOW | 8,737 | 367 | **15%** (13%-17%) | 19% | 26% |
| old HIGH | 109 | 29 | **28%** (17%-38%) | 23% | 0% |
| old NORMAL | 22,135 | 293 | **24%** (23%-26%) | 22% | 100% |
| old LOW | 0 | 0 | - | - | - |

v2's actual alerts (chance 29% or more, nothing gated, one per match per 10 min): 407 on 189 matches, a goal followed within 10 min 27% against 22% normally.
The old signal gave a number on 293 of 370 matches; it said exactly 38% (its fixed default) on 72% of those minutes. Its only alerts were 62 half-time bets on the final total (e.g. "back Under 3.5"), not goal-timing calls; 42 could be linked to a scored match and 32 of them (76%) were right.

- **Goals and what v2 was saying just before:** of 891 goals it was watching, 230 (26%) came while it said HIGH, 460 (52%) NORMAL, 201 (23%) LOW; it spent 23% / 51% / 26% of playing time in each. (138 more goals came with no v2 call in the 3 min before: no feed, half time or gated.)
- **Warning:** 415 goals had a HIGH in the 10 minutes before; the HIGH had been on for 8.8 min on average (median 5.4).
- **HIGH with no goal:** 1175 of 1660 HIGH spells (71%) passed with no goal in the 10 minutes after.

**By half, score and late on (v2): goal within 10 min when it said HIGH / NORMAL / LOW, with the plain average for those minutes)**

| | HIGH | NORMAL | LOW |
|---|---|---|---|
| first half | 19% of 4,223 (avg 20%) | 23% of 9,056 (avg 22%) | 19% of 2,201 (avg 21%) |
| second half | 28% of 3,428 (avg 23%) | 25% of 7,911 (avg 23%) | 14% of 6,536 (avg 18%) |
| level | 21% of 4,596 (avg 21%) | 24% of 8,582 (avg 23%) | 14% of 2,534 (avg 20%) |
| one-goal game | 29% of 1,932 (avg 22%) | 23% of 6,877 (avg 22%) | 15% of 3,318 (avg 19%) |
| two or more apart | 21% of 1,123 (avg 21%) | 25% of 1,508 (avg 20%) | 16% of 2,885 (avg 18%) |
| last 15 min (75+) | 30% of 949 (avg 16%) | 23% of 2,271 (avg 16%) | 9% of 4,556 (avg 16%) |

## What would make it sharper (from 21-22 Nov; written once by session 22, not rewritten nightly)

Looked at the 661 goals v2 called NORMAL or LOW just before, and the 5,882 HIGH minutes with no goal, against the facts and prices known at that minute (sc_diag.py).

1. **Its HIGH only works in the second half; in the first half it is noise.** Second half: 28% against 23% normal (3,428 calls); last 15 minutes: 30% against 16% (949). First half: 19% against 20% (4,223 calls), which is more than half of all its HIGH calls. **Try:** a separate first-half cut-off, or no HIGH before minute 45. Session 13 tested the first half as an input, not as its own cut-off.
2. **The match facts we hold would not have caught the missed goals.** A shot on target in the last 5 minutes: 100 of 297 missed-goal minutes (34%) against 3,363 of 9,914 quiet minutes (34%), so no difference. Two or more corners: 11% against 10%. These stats exist on only 52% of minutes. Red cards are known on only 4% of minutes (19 goals), too few to test. No feed records substitutions. A team chasing late (one-goal game from minute 70) scored **less** often when v2 said NORMAL/LOW (13.5% against 17.6% normal, 2,813 calls). **Try:** nothing from these feeds yet. A substitutions feed would be the one new fact worth adding.
3. **The over price not drifting is the only thing that lifted the missed goals.** On NORMAL/LOW minutes where the over price was drifting slower than normal over 5 minutes, a goal followed 24.4% of the time against 22.5% normal (4,056 calls, 363 matches): +2 points. It is already an input, but only up to 5 minutes. **Try:** the same measure over 10-15 minutes, with more weight late in the second half where finding 1 says the signal works.

## Day by day (rewritten 23:30 UK each night)

| date | matches | calls | HIGH: goal within 10 | NORMAL | LOW | all minutes |
|---|---|---|---|---|---|---|
| 2026-11-21 | 264 | 23,197 | 23% (5,562) | 23% | 15% (5,807) | 21% |
| 2026-11-22 | 106 | 10,158 | 22% (2,089) | 24% | 14% (2,930) | 21% |

## Three matches, five minutes at a time

v2 = version 2's chance of a goal in the next 10 minutes; usual rate = how often a goal followed in the same minute band and score on 2-19 Nov (what HIGH / LOW is measured against); old signal = the old model's chance and its band against its own usual level. RIGHT/WRONG marks only HIGH and LOW.

### Most money matched on 2026-11-22 with full data (£1,751,793 on match odds): Racing Santander v Real Sociedad (live)
Goals (Betfair suspension times): 7' 1-0, 8' 2-0, 45' 2-1, 61' 2-2, 68' 3-2. On these lines: 6 right, 10 wrong.

| min | score | v2: goal in next 10 min | usual rate | old signal | next 10 min | call |
|---|---|---|---|---|---|---|
| 1 | 0-0 | 24% **NORMAL** | 20% | none | GOAL 7' (1-0), GOAL 8' (2-0) |  |
| 5 | 0-0 | 25% **HIGH** | 20% | 41% NORMAL | GOAL 7' (1-0), GOAL 8' (2-0) | RIGHT |
| 10 | 2-0 | 20% **HIGH** | 11% | 47% NORMAL | no goal | WRONG |
| 15 | 2-0 | 23% **HIGH** | 11% | none | no goal | WRONG |
| 20 | 2-0 | 24% **HIGH** | 12% | none | no goal | WRONG |
| 25 | 2-0 | 23% **HIGH** | 12% | none | no goal | WRONG |
| 31 | 2-0 | 24% **HIGH** | 18% | none | no goal | WRONG |
| 35 | 2-0 | 24% **HIGH** | 18% | none | no goal | WRONG |
| 40 | 2-0 | 24% **HIGH** | 18% | none | GOAL 45' (2-1) | RIGHT |
| HT | | | | | | |
| 47 | 2-1 | 29% **NORMAL** | 24% | 51% HIGH | no goal |  |
| 50 | 2-1 | 30% **HIGH** | 24% | 41% NORMAL | GOAL 61' (2-2) | RIGHT |
| 55 | 2-1 | 30% **HIGH** | 24% | 41% NORMAL | GOAL 61' (2-2), GOAL 68' (3-2) | RIGHT |
| 60 | 2-1 | 30% **HIGH** | 24% | 41% NORMAL | GOAL 68' (3-2) | RIGHT |
| 65 | 2-2 | 33% **NORMAL** | 29% | 44% NORMAL | GOAL 68' (3-2) |  |
| 70 | 3-2 | 29% **HIGH** | 22% | 41% NORMAL | no goal | WRONG |
| 75 | 3-2 | 35% **HIGH** | 22% | 53% HIGH | no goal | WRONG |
| 80 | 3-2 | 33% **HIGH** | 20% | 41% NORMAL | no goal | WRONG |
| 85 | 3-2 | 31% **HIGH** | 20% | 45% NORMAL | no goal | WRONG |
| 90 | 3-2 | 14% **LOW** | 20% | none | no goal | RIGHT |

### Best called on 2026-11-22 (100% of 37 HIGH/LOW calls right): PFC Levski Sofia v Lokomotiv Sofia (live)
Goals (Betfair suspension times): 20' 1-0, 35' 2-0. On these lines: 1 right, 0 wrong.

| min | score | v2: goal in next 10 min | usual rate | old signal | next 10 min | call |
|---|---|---|---|---|---|---|
| 20 | 1-0 | 24% **NORMAL** | 25% | none | no goal |  |
| 26 | 1-0 | 26% **NORMAL** | 25% | none | GOAL 35' (2-0) |  |
| 31 | 1-0 | 25% **NORMAL** | 24% | none | GOAL 35' (2-0) |  |
| 35 | 2-0 | 15% **NORMAL** | 18% | none | no goal |  |
| 40 | 2-0 | 17% **NORMAL** | 18% | none | no goal |  |
| HT | | | | | | |
| 50 | 2-0 | 17% **NORMAL** | 20% | none | no goal |  |
| 55 | 2-0 | 16% **LOW** | 20% | none | no goal | RIGHT |

### Worst called on 2026-11-22 (15% of 66 HIGH/LOW calls right): Hull v Brighton (live)
Goals (Betfair suspension times): 90' 1-0, 90' 2-0. On these lines: 1 right, 12 wrong.

| min | score | v2: goal in next 10 min | usual rate | old signal | next 10 min | call |
|---|---|---|---|---|---|---|
| 2 | 0-0 | 14% **LOW** | 20% | 41% NORMAL | no goal | RIGHT |
| 5 | 0-0 | 23% **NORMAL** | 20% | 42% NORMAL | no goal |  |
| 11 | 0-0 | 26% **HIGH** | 20% | 42% NORMAL | no goal | WRONG |
| 15 | 0-0 | 26% **HIGH** | 20% | 42% NORMAL | no goal | WRONG |
| 20 | 0-0 | 28% **HIGH** | 18% | 42% NORMAL | no goal | WRONG |
| 25 | 0-0 | 27% **HIGH** | 18% | 42% NORMAL | no goal | WRONG |
| 30 | 0-0 | 27% **HIGH** | 18% | 42% NORMAL | no goal | WRONG |
| 35 | 0-0 | 27% **HIGH** | 15% | 41% NORMAL | no goal | WRONG |
| 40 | 0-0 | 27% **HIGH** | 15% | 48% NORMAL | no goal | WRONG |
| HT | | | | | | |
| 47 | 0-0 | 31% **HIGH** | 21% | 47% NORMAL | no goal | WRONG |
| 50 | 0-0 | 32% **HIGH** | 21% | 42% NORMAL | no goal | WRONG |
| 55 | 0-0 | 32% **HIGH** | 21% | 42% NORMAL | no goal | WRONG |
| 60 | 0-0 | 34% **HIGH** | 21% | 42% NORMAL | no goal | WRONG |
| 65 | 0-0 | 32% **NORMAL** | 29% | 41% NORMAL | no goal |  |
| 70 | 0-0 | 35% **NORMAL** | 29% | 42% NORMAL | no goal |  |
| 76 | 0-0 | 36% **NORMAL** | 29% | 42% NORMAL | no goal |  |
| 80 | 0-0 | 32% **NORMAL** | 29% | 42% NORMAL | GOAL 90' (1-0) |  |
| 85 | 0-0 | 33% **NORMAL** | 29% | 45% NORMAL | GOAL 90' (1-0), GOAL 90' (2-0) |  |
| 90 | 0-0 | 23% **LOW** | 29% | none | GOAL 90' (2-0) | WRONG |

_Built 2026-11-22 18:38 UTC by /root/pe-sports/goaltrade/sc_build.py + sc_report.py (session 22). Scorecard only._
