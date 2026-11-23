# Goal signal against real games (2026-11-22) - tier one, money £0 (scorecard only, no bets, no paper)

**On 432 matches over 2 days, when the signal said HIGH a goal followed within 10 minutes 24% of the time, against 22% normally for those same minutes and scores; when it said LOW, 15% (normally 20%).**
Is that enough to trust? Not yet. Resampling whole matches, HIGH could plausibly be anywhere from 22% to 26% and LOW from 13% to 17%. HIGH beats normal even at the bottom of its range. LOW is below normal even at the top of its range. Each extra day narrows it; a week of nights (the table below fills itself) should roughly halve the range.

_Data: 237 matches kicked off and finished on the stream; 180 had a score feed; 168 could be scored (168 live by v2, 0 replayed on the recorded ticks; the scorecard uses the in-play minutes of these). v2 has run live since 21 Nov 17:18 UTC: every match that kicked off before then is replayed, every later one is its live record (list: goaltrade/cache/sc_match_*.parquet, column live); replay and live agree to a median 0.3 points where both exist. Goals in those matches: 469 on the score feeds; 444 (95%) matched to a Betfair suspension, the feeds a median 1.4 min behind it; 25 did not match (timed from the feed less 1.5 min). The other way round, 297 suspensions with a 10% price move had no goal on any feed: penalties awarded, red cards, VAR, goals ruled out, or a price measured on a thin outsider - so they are counted, not used._

## Scorecard: every call

Each call is one minute of one match. "Normal" = the average for the same minutes and scores. Range = 95% by resampling matches.

| signal says | calls | matches | goal within 10 min | normal | share of playing time |
|---|---|---|---|---|---|
| v2 HIGH | 3,581 | 161 | **25%** (21%-29%) | 21% | 22% |
| v2 NORMAL | 7,898 | 168 | **25%** (22%-28%) | 24% | 49% |
| v2 LOW | 4,519 | 168 | **14%** (12%-17%) | 20% | 28% |
| old HIGH | 22 | 8 | **23%** (5%-55%) | 21% | 0% |
| old NORMAL | 9,470 | 123 | **27%** (24%-30%) | 23% | 100% |
| old LOW | 0 | 0 | - | - | - |

v2's actual alerts (chance 29% or more, nothing gated, one per match per 10 min): 187 on 89 matches, a goal followed within 10 min 30% against 23% normally.
The old signal gave a number on 123 of 168 matches; it said exactly 38% (its fixed default) on 82% of those minutes. Its only alerts were 37 half-time bets on the final total (e.g. "back Under 3.5"), not goal-timing calls; 26 could be linked to a scored match and 19 of them (73%) were right.

- **Goals and what v2 was saying just before:** of 433 goals it was watching, 115 (27%) came while it said HIGH, 227 (52%) NORMAL, 91 (21%) LOW; it spent 22% / 49% / 28% of playing time in each. (62 more goals came with no v2 call in the 3 min before: no feed, half time or gated.)
- **Warning:** 206 goals had a HIGH in the 10 minutes before; the HIGH had been on for 9.5 min on average (median 5.7).
- **HIGH with no goal:** 501 of 743 HIGH spells (67%) passed with no goal in the 10 minutes after.

**By half, score and late on (v2): goal within 10 min when it said HIGH / NORMAL / LOW, with the plain average for those minutes)**

| | HIGH | NORMAL | LOW |
|---|---|---|---|
| first half | 20% of 1,886 (avg 19%) | 25% of 3,992 (avg 24%) | 18% of 1,140 (avg 22%) |
| second half | 31% of 1,695 (avg 24%) | 25% of 3,906 (avg 24%) | 13% of 3,379 (avg 19%) |
| level | 22% of 1,964 (avg 22%) | 26% of 3,884 (avg 24%) | 14% of 1,148 (avg 22%) |
| one-goal game | 31% of 851 (avg 21%) | 24% of 3,195 (avg 23%) | 14% of 1,742 (avg 19%) |
| two or more apart | 26% of 766 (avg 21%) | 24% of 819 (avg 21%) | 15% of 1,629 (avg 19%) |
| last 15 min (75+) | 30% of 448 (avg 16%) | 28% of 1,073 (avg 18%) | 10% of 2,485 (avg 17%) |

## What would make it sharper (from 21-22 Nov; written once by session 22, not rewritten nightly)

Looked at the 661 goals v2 called NORMAL or LOW just before, and the 5,882 HIGH minutes with no goal, against the facts and prices known at that minute (sc_diag.py).

1. **Its HIGH only works in the second half; in the first half it is noise.** Second half: 28% against 23% normal (3,428 calls); last 15 minutes: 30% against 16% (949). First half: 19% against 20% (4,223 calls), which is more than half of all its HIGH calls. **Try:** a separate first-half cut-off, or no HIGH before minute 45. Session 13 tested the first half as an input, not as its own cut-off.
2. **The match facts we hold would not have caught the missed goals.** A shot on target in the last 5 minutes: 100 of 297 missed-goal minutes (34%) against 3,363 of 9,914 quiet minutes (34%), so no difference. Two or more corners: 11% against 10%. These stats exist on only 52% of minutes. Red cards are known on only 4% of minutes (19 goals), too few to test. No feed records substitutions. A team chasing late (one-goal game from minute 70) scored **less** often when v2 said NORMAL/LOW (13.5% against 17.6% normal, 2,813 calls). **Try:** nothing from these feeds yet. A substitutions feed would be the one new fact worth adding.
3. **The over price not drifting is the only thing that lifted the missed goals.** On NORMAL/LOW minutes where the over price was drifting slower than normal over 5 minutes, a goal followed 24.4% of the time against 22.5% normal (4,056 calls, 363 matches): +2 points. It is already an input, but only up to 5 minutes. **Try:** the same measure over 10-15 minutes, with more weight late in the second half where finding 1 says the signal works.

## Day by day (rewritten 23:30 UK each night)

| date | matches | calls | HIGH: goal within 10 | NORMAL | LOW | all minutes |
|---|---|---|---|---|---|---|
| 2026-11-21 | 264 | 23,197 | 23% (5,562) | 23% | 15% (5,807) | 21% |
| 2026-11-22 | 168 | 15,998 | 25% (3,581) | 25% | 14% (4,519) | 22% |

## Three matches, five minutes at a time

v2 = version 2's chance of a goal in the next 10 minutes; usual rate = how often a goal followed in the same minute band and score on 2-19 Nov (what HIGH / LOW is measured against); old signal = the old model's chance and its band against its own usual level. RIGHT/WRONG marks only HIGH and LOW.

### Most money matched on 2026-11-22 with full data (£1,833,580 on match odds): Atalanta v Inter (live)
Goals (Betfair suspension times): 16' 0-1, 33' 0-2, 35' 1-2, 53' 1-3, 73' 2-3, 74' 2-4, 81' 3-4, 90' 4-4. On these lines: 8 right, 4 wrong.

| min | score | v2: goal in next 10 min | usual rate | old signal | next 10 min | call |
|---|---|---|---|---|---|---|
| 1 | 0-0 | 8% **LOW** | 20% | 40% NORMAL | no goal | RIGHT |
| 5 | 0-0 | 22% **NORMAL** | 20% | 40% NORMAL | no goal |  |
| 10 | 0-0 | 25% **HIGH** | 20% | 40% NORMAL | GOAL 16' (0-1) | RIGHT |
| 16 | 0-0 | 29% **HIGH** | 18% | 40% NORMAL | no goal | WRONG |
| 20 | 0-1 | 25% **NORMAL** | 25% | 40% NORMAL | no goal |  |
| 25 | 0-1 | 24% **NORMAL** | 25% | 40% NORMAL | GOAL 33' (0-2), GOAL 35' (1-2) |  |
| 30 | 0-1 | 26% **NORMAL** | 25% | 40% NORMAL | GOAL 33' (0-2), GOAL 35' (1-2) |  |
| 35 | 0-2 | 22% **NORMAL** | 18% | none | no goal |  |
| 40 | 1-2 | 28% **NORMAL** | 24% | 40% NORMAL | no goal |  |
| HT | | | | | | |
| 46 | 1-2 | 30% **HIGH** | 24% | 40% NORMAL | GOAL 53' (1-3) | RIGHT |
| 50 | 1-2 | 31% **HIGH** | 24% | 40% NORMAL | GOAL 53' (1-3) | RIGHT |
| 55 | 1-3 | 32% **HIGH** | 20% | 40% NORMAL | no goal | WRONG |
| 61 | 1-3 | 32% **HIGH** | 19% | 40% NORMAL | no goal | WRONG |
| 65 | 1-3 | 32% **HIGH** | 19% | 40% NORMAL | GOAL 73' (2-3), GOAL 74' (2-4) | RIGHT |
| 71 | 1-3 | 32% **HIGH** | 19% | 40% NORMAL | GOAL 73' (2-3), GOAL 74' (2-4), GOAL 81' (3-4) | RIGHT |
| 75 | 2-3 | 19% **NORMAL** | 22% | 40% NORMAL | GOAL 81' (3-4) |  |
| 80 | 2-4 | 32% **HIGH** | 16% | none | GOAL 90' (4-4) | RIGHT |
| 85 | 3-4 | 33% **HIGH** | 20% | 43% NORMAL | GOAL 90' (4-4) | RIGHT |
| 90 | 3-4 | 11% **LOW** | 20% | none | GOAL 90' (4-4) | WRONG |

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

_Built 2026-11-23 00:52 UTC by /root/pe-sports/goaltrade/sc_build.py + sc_report.py (session 22). Scorecard only._
