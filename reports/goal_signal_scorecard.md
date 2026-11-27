# Goal signal against real games (2026-11-27) - tier one, money £0 (scorecard only, no bets, no paper)

**On 755 matches over 7 days, when the signal said HIGH a goal followed within 10 minutes 23% of the time, against 21% normally for those same minutes and scores; when it said LOW, 14% (normally 19%).**
Is that enough to trust? Not yet. Resampling whole matches, HIGH could plausibly be anywhere from 22% to 25% and LOW from 13% to 15%. HIGH beats normal even at the bottom of its range. LOW is below normal even at the top of its range. Each extra day narrows it; a week of nights (the table below fills itself) should roughly halve the range.

_Data: 7 matches kicked off and finished on the stream; 4 had a score feed; 4 could be scored (2 live by v2, 2 replayed on the recorded ticks; the scorecard uses the in-play minutes of these). v2 has run live since 21 Nov 17:18 UTC: every match that kicked off before then is replayed, every later one is its live record (list: goaltrade/cache/sc_match_*.parquet, column live); replay and live agree to a median 0.3 points where both exist. Goals in those matches: 12 on the score feeds; 12 (100%) matched to a Betfair suspension, the feeds a median 1.1 min behind it; 0 did not match (timed from the feed less 1.5 min). The other way round, 8 suspensions with a 10% price move had no goal on any feed: penalties awarded, red cards, VAR, goals ruled out, or a price measured on a thin outsider - so they are counted, not used._

## Scorecard: every call

Each call is one minute of one match. "Normal" = the average for the same minutes and scores. Range = 95% by resampling matches.

| signal says | calls | matches | goal within 10 min | normal | share of playing time |
|---|---|---|---|---|---|
| v2 HIGH | 98 | 4 | **19%** (0%-44%) | 21% | 25% |
| v2 NORMAL | 213 | 4 | **24%** (14%-32%) | 25% | 55% |
| v2 LOW | 79 | 4 | **14%** (0%-22%) | 11% | 20% |
| old HIGH | 0 | 0 | - | - | - |
| old NORMAL | 146 | 2 | **17%** (-) | 23% | 100% |
| old LOW | 0 | 0 | - | - | - |

v2's actual alerts (chance 29% or more, nothing gated, one per match per 10 min): 6 on 3 matches, a goal followed within 10 min 17% against 30% normally.
The old signal gave a number on 2 of 4 matches; it said exactly 38% (its fixed default) on 100% of those minutes. Its only alerts were 7 half-time bets on the final total (e.g. "back Under 3.5"), not goal-timing calls; 0 could be linked to a scored match and 0 of them (-) were right.

- **Goals and what v2 was saying just before:** of 12 goals it was watching, 2 (17%) came while it said HIGH, 8 (67%) NORMAL, 2 (17%) LOW; it spent 25% / 55% / 20% of playing time in each. (0 more goals came with no v2 call in the 3 min before: no feed, half time or gated.)
- **Warning:** 3 goals had a HIGH in the 10 minutes before; the HIGH had been on for 10.1 min on average (median 12.5).
- **HIGH with no goal:** 17 of 20 HIGH spells (85%) passed with no goal in the 10 minutes after.

**By half, score and late on (v2): goal within 10 min when it said HIGH / NORMAL / LOW, with the plain average for those minutes)**

| | HIGH | NORMAL | LOW |
|---|---|---|---|
| first half | 0% of 11 (avg 12%) | 27% of 153 (avg 25%) | 25% of 12 (avg 33%) |
| second half | 22% of 87 (avg 22%) | 18% of 60 (avg 23%) | 12% of 67 (avg 7%) |
| level | 43% of 23 (avg 40%) | 39% of 54 (avg 41%) | 75% of 4 (avg 62%) |
| one-goal game | 0% of 26 (avg 2%) | 24% of 123 (avg 23%) | 3% of 35 (avg 6%) |
| two or more apart | 18% of 49 (avg 22%) | 3% of 36 (avg 6%) | 18% of 40 (avg 10%) |
| last 15 min (75+) | 0% of 12 (avg 0%) | 32% of 28 (avg 35%) | 2% of 58 (avg 2%) |

## What would make it sharper (from 21-22 Nov; written once by session 22, not rewritten nightly)

Looked at the 661 goals v2 called NORMAL or LOW just before, and the 5,882 HIGH minutes with no goal, against the facts and prices known at that minute (sc_diag.py).

1. **Its HIGH only works in the second half; in the first half it is noise.** Second half: 28% against 23% normal (3,428 calls); last 15 minutes: 30% against 16% (949). First half: 19% against 20% (4,223 calls), which is more than half of all its HIGH calls. **Try:** a separate first-half cut-off, or no HIGH before minute 45. Session 13 tested the first half as an input, not as its own cut-off.
2. **The match facts we hold would not have caught the missed goals.** A shot on target in the last 5 minutes: 100 of 297 missed-goal minutes (34%) against 3,363 of 9,914 quiet minutes (34%), so no difference. Two or more corners: 11% against 10%. These stats exist on only 52% of minutes. Red cards are known on only 4% of minutes (19 goals), too few to test. No feed records substitutions. A team chasing late (one-goal game from minute 70) scored **less** often when v2 said NORMAL/LOW (13.5% against 17.6% normal, 2,813 calls). **Try:** nothing from these feeds yet. A substitutions feed would be the one new fact worth adding.
3. **The over price not drifting is the only thing that lifted the missed goals.** On NORMAL/LOW minutes where the over price was drifting slower than normal over 5 minutes, a goal followed 24.4% of the time against 22.5% normal (4,056 calls, 363 matches): +2 points. It is already an input, but only up to 5 minutes. **Try:** the same measure over 10-15 minutes, with more weight late in the second half where finding 1 says the signal works.

## Day by day (rewritten 23:30 UK each night)

**SECOND VERSION BEATS THE CURRENT ONE over 7 days on late HIGH (within chance). LOW (points below normal): current +3.0 (15,552 calls), second +2.8 (15,722), difference -0.2 (range -0.5 to +0.2); late HIGH (points above normal): current +11.1 (2,252 calls), second +11.4 (2,219), difference +0.2 (range -0.8 to +1.1).**

Second version = fitted on days before 21 Nov; no HIGH before the second half (so its HIGH is second half only); the over price not drifting measured over 5, 10 and 15 minutes, weighted more late on. Scored from the recorded ticks on the same calls; late HIGH = HIGH from minute 75, goal within 10 (calls).

| date | matches | calls | HIGH: goal within 10 | NORMAL | LOW | late HIGH | 2nd version HIGH | 2nd NORMAL | 2nd LOW | 2nd late HIGH | all minutes |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-11-21 | 264 | 23,197 | 23% (5,562) | 23% | 15% (5,807) | 31% (699) | 27% (2,555) | 23% | 16% (5,587) | 30% (706) | 21% |
| 2026-11-22 | 174 | 16,614 | 25% (3,766) | 25% | 14% (4,638) | 29% (481) | 30% (1,829) | 24% | 17% (3,840) | 30% (468) | 22% |
| 2026-11-23 | 67 | 6,424 | 17% (1,684) | 26% | 10% (1,536) | 22% (243) | 21% (857) | 23% | 13% (1,248) | 22% (241) | 20% |
| 2026-11-24 | 109 | 10,779 | 24% (2,820) | 26% | 15% (2,760) | 16% (355) | 26% (1,383) | 25% | 18% (2,269) | 15% (327) | 22% |
| 2026-11-25 | 79 | 7,797 | 22% (1,836) | 24% | 14% (1,943) | 24% (255) | 28% (909) | 22% | 18% (1,566) | 25% (261) | 21% |
| 2026-11-26 | 58 | 5,613 | 26% (1,788) | 27% | 11% (1,333) | 27% (207) | 27% (862) | 27% | 14% (1,135) | 30% (204) | 23% |
| 2026-11-27 | 4 | 390 | 19% (98) | 24% | 14% (79) | 0% (12) | 23% (87) | 23% | 13% (77) | 0% (12) | 21% |


**Every version beside the others, on the same calls** (points, calls in brackets: LOW = how far BELOW normal the goals were, HIGH and late HIGH (from minute 75) = how far ABOVE; bigger is better; normal = same minutes and scores; version 3 is always scored by a model fitted before that day)

| date | calls | old: LOW / HIGH / late HIGH | 2: LOW / HIGH / late HIGH | 2b: LOW / HIGH / late HIGH | 3: LOW / HIGH / late HIGH | best LOW | best late HIGH |
|---|---|---|---|---|---|---|---|
| 2026-11-21 | 22,091 | - / +5.4 (90) / -2.1 (8) | +3.2 (5,046) / +1.9 (5,517) / +15.8 (696) | +3.2 (5,076) / +3.5 (2,551) / +15.0 (703) | +7.0 (4,508) / +3.2 (7,468) / +11.0 (1,173) | 3 | 2 |
| 2026-11-22 | 15,579 | - / -5.0 (27) / +0.4 (5) | +2.4 (3,664) / +3.5 (3,763) / +14.6 (479) | +1.7 (3,677) / +6.1 (1,826) / +15.4 (465) | +5.6 (3,077) / +3.8 (5,741) / +14.0 (866) | 3 | 2b |
| 2026-11-23 | 5,674 | - / -24.3 (4) / - | +6.5 (1,132) / -5.9 (1,547) / +3.1 (214) | +6.3 (1,148) / -4.7 (776) / +2.9 (209) | +8.5 (1,242) / +0.2 (1,952) / +9.5 (354) | 3 | 3 |
| 2026-11-24 | 10,203 | - / +1.8 (7) / -25.9 (1) | +0.5 (2,189) / +2.3 (2,817) / +1.5 (355) | +0.8 (2,207) / +2.5 (1,380) / -0.2 (327) | +7.8 (1,771) / +5.9 (4,795) / +9.3 (666) | 3 | 3 |
| 2026-11-25 | 7,260 | - / -5.6 (11) / -16.1 (1) | +1.2 (1,486) / +1.1 (1,835) / +8.6 (255) | +0.8 (1,507) / +5.2 (904) / +9.9 (259) | +6.5 (1,429) / +5.2 (2,683) / +9.9 (389) | 3 | 3 |
| 2026-11-26 | 5,293 | -0.3 (112) / +8.9 (35) / +51.6 (6) | +5.5 (1,036) / +3.9 (1,787) / +12.4 (207) | +5.4 (1,095) / +3.4 (862) / +15.9 (204) | +1.1 (782) / +3.5 (2,292) / +3.3 (329) | 2 | 2b |
| 2026-11-27 | 383 | - / - / - | +3.7 (72) / -4.3 (98) / -15.0 (12) | +3.6 (77) / -1.3 (87) / -15.0 (12) | +1.7 (83) / -3.6 (145) / -14.0 (37) | 2 | 3 |
| **all days** | 66,483 | -0.3 (112) / +3.0 (174) / +12.1 (21) | +2.8 (14,625) / +1.7 (17,364) / +10.7 (2,218) | +2.6 (14,787) / +3.3 (8,386) / +10.9 (2,179) | +6.5 (12,892) / +3.8 (25,076) / +10.2 (3,814) | 3 | 2b |

**The trial rules read version 2 (since 2026-11-24).** They switch when a newer version beats it for a full week (7 scored days) on LOW and on late HIGH: no newer version beat version 2 on both LOW and late HIGH over the last 7 scored days.

Live version 3 against its replay on 2026-11-27: 382 moments, correlation 0.97, typical gap 0.5 points. (Under 0.80 the trial may not switch to version 3.)

Live events collector, last 24 hours: 164 Betfair matches, 132 found on the feed, live stats for 48; goals arrive a median 43 s after the Betfair suspension (18 goals matched); calls used 5,927 of its 30,000.

## Version 3 (session 25, 24 Nov)

**Money: £0 (tier one; paper and scorecard only, no bets). Verdict: NOT YET as a money maker, WORKS as a better reader of quiet spells. Next test: automatic each night; the full-week comparison is read on 28 Nov (night of 27 Nov), and the first weekly refit is 30 Nov.**

**On 1,486 matches neither version had seen (119,567 calls, 31 Oct, 1, 10-12 and 20-24 Nov), goal within 10 minutes against normal for the same minutes and scores, version 2 then version 3: HIGH 23.0% against 21.5% (+1.4 points) then 26.8% against 22.2% (+4.6); NORMAL 23.2% against 22.4% then 22.7% against 22.6%; LOW 17.0% against 20.8% (-3.8) then 11.8% against 19.5% (-7.7); late HIGH (minute 75 on) 24.6% against 18.6% (+6.0) then 25.1% against 18.2% (+6.9).**

At the SAME number of calls as version 2, version 3 less version 2 (95% range, whole matches resampled): HIGH +3.2 points [+2.0, +4.3]; LOW -3.6 [-4.7, -2.4] (further below normal = better); late HIGH +0.9 [-1.9, +3.7] (could be nothing). First-half HIGH, which was noise in version 2 (+0.8), is +4.1 in version 3.

**What does NOT pass, or is not yet known:** (1) HIGH is not money: version 3's HIGH was +0.4 points [-0.8, +1.5] against what the goals prices already implied, so the price knew. Its LOW was -2.2 points [-3.2, -1.1] below what the price implied (version 2: -2.9); but that price is our own scaled estimate from the minute prices, not an offer anyone could take, so it is a lead, not a result. **Version 2's LOW was as far below the price as version 3's, so version 3's extra LOW points are mostly things the price already knew;** the trade to test next is backing the under on LOW spells, at prices actually offered, through the existing paper trial (A+P rules), first read 1 Dec. (2) Late HIGH is not proven better: on 21-23 Nov alone version 2 was +12.7 points and version 3 +10.7. (3) Events delay: only 11 goals matched so far. (4) The share of minutes with live stats after the new collector is not measured yet (first full day tonight). (5) Formations and line-ups are collected but not tried as inputs; version 2's stream tick inputs are not in version 3.

**Is it too good?** I looked for the flaw. The gain is the same with the first 1, 2, 3, 4 and 5 minutes of the window thrown away (a price that had already seen a goal would vanish: HIGH stayed +4.6 to +4.8, LOW -6.9 to -7.8), on the matches with a real score feed only (HIGH +4.3, LOW -7.6), and with minutes 35-45 and 80+ removed (a 10-minute window that hits half time or the end holds fewer goals; HIGH +3.4, LOW -6.0). But against a normal that knows the exact minute, the points are smaller: version 2 HIGH +0.9, LOW -2.4, late HIGH +1.8; version 3 HIGH +3.3, LOW -4.3, late HIGH +3.3. So about 40% of the scorecard's LOW points, in both versions, are just the clock. 10 and 11 Nov (about 6,000 calls) have no score feed and prices on half the minutes; they look extreme and carry little weight.

### Which changes were kept, and the number that decided each

Fitted and decided only on version 2's own days (2-9, 13-19 Nov; 79,342 calls, 1,042 matches), in blocks of days left out in turn; points = separation at fixed call shares against the exact-minute normal (LOW + HIGH + late HIGH, or the part that question is for). Kept only if the points rise AND the log loss does not get worse; the rule was written before any result was seen (v3_criteria.md). The unseen days above were read once, after this was frozen; later looks at them were only to search for flaws, and nothing was changed as a result.

| question | change | points | change in points | change in log loss | verdict |
|---|---|---|---|---|---|
| one question | (reference) version 2 itself, which has seen these days | +8.4 | - | - | reference |
| one question | (reference) the years of history alone | +15.2 | - | - | reference |
| one question | (reference) the history, one model for the match | +16.3 | - | - | reference |
| goal coming | START: version 2's price inputs from the minute sweeps, one model | +3.9 | - | - | START |
| goal coming | + the years of history (one model for the whole match) | +12.8 | +8.84 | -0.00854 | KEPT |
| goal coming | + the years of history, fitted per part of the match | +12.2 | -0.58 | +0.00052 | DROPPED |
| goal coming | - version 2's own price inputs (history already holds them) | +11.5 | -1.24 | +0.00133 | DROPPED |
| goal coming | fit also on matches whose goals were read from the market | +11.6 | -1.15 | -0.00001 | DROPPED |
| goal coming | + all the goals lines together | +13.6 | +0.84 | +0.00008 | DROPPED |
| goal coming | + goal expectation against the clock, 5 / 10 / 15 min | +13.1 | +0.36 | +0.00055 | DROPPED |
| goal coming | + money traded | +10.8 | -2.01 | +0.00161 | DROPPED |
| goal coming | + money waiting | +12.2 | -0.59 | -0.00019 | DROPPED |
| goal coming | + markets disagreeing | +15.1 | +2.34 | -0.00112 | KEPT |
| goal coming | + score state, who needs a goal, time since the last goal | +13.7 | -1.41 | +0.00127 | DROPPED |
| goal coming | + which side is pressing (live stats) | +14.5 | -0.65 | +0.00047 | DROPPED |
| goal coming | + each side's own goal expectation moving | +15.4 | +0.29 | -0.00017 | KEPT |
| goal coming | + cards, substitutions, VAR | +15.2 | -0.20 | -0.00005 | DROPPED |
| goal coming | separate fits: first half, 45-70, 70-90+ | +12.0 | -3.39 | +0.00565 | DROPPED |
| goal coming | trees instead of logistic regression | +12.5 | -2.91 | +0.00005 | DROPPED |
| quiet | START: version 2's price inputs from the minute sweeps, one model | +2.5 | - | - | START |
| quiet | + the years of history (one model for the whole match) | +5.1 | +2.61 | -0.00854 | KEPT |
| quiet | + the years of history, fitted per part of the match | +4.9 | -0.20 | +0.00052 | DROPPED |
| quiet | - version 2's own price inputs (history already holds them) | +4.5 | -0.60 | +0.00133 | DROPPED |
| quiet | fit also on matches whose goals were read from the market | +4.3 | -0.80 | -0.00001 | DROPPED |
| quiet | + all the goals lines together | +5.4 | +0.24 | +0.00008 | DROPPED |
| quiet | + goal expectation against the clock, 5 / 10 / 15 min | +5.0 | -0.07 | +0.00055 | DROPPED |
| quiet | + money traded | +5.1 | -0.06 | +0.00161 | DROPPED |
| quiet | + money waiting | +5.1 | +0.01 | -0.00019 | KEPT |
| quiet | + markets disagreeing | +5.4 | +0.27 | -0.00065 | KEPT |
| quiet | + score state, who needs a goal, time since the last goal | +4.7 | -0.68 | +0.00126 | DROPPED |
| quiet | + which side is pressing (live stats) | +5.3 | -0.06 | +0.00051 | DROPPED |
| quiet | + each side's own goal expectation moving | +5.4 | +0.04 | -0.00014 | KEPT |
| quiet | + cards, substitutions, VAR | +5.5 | +0.06 | -0.00003 | KEPT |
| quiet | separate fits: first half, 45-70, 70-90+ | +4.3 | -1.21 | +0.00769 | DROPPED |
| quiet | trees instead of logistic regression | +6.0 | +0.48 | -0.00047 | KEPT |
| quiet | asked over 15 minutes instead of 10 | +6.0 | +0.05 | +0.00090 | DROPPED |
| quiet | asked over 20 minutes instead of 10 | +5.8 | -0.20 | +0.00163 | DROPPED |
| quiet | asked over 10, 15 and 20 together | +6.0 | +0.03 | +0.00035 | DROPPED |

Two questions (goal coming and quiet) against one model for both: 21.37 against 20.82 points, KEPT by 0.55. That is a small gain. **Dropped as a whole:** separate fits for first half / 45-70 / 70-90+ (-3.39 points) and 15- and 20-minute versions of the quiet question. The years of history say the same: no better when split by part of the match (ranking score 0.5967 split, 0.5975 as one).
What carried it is the years of history (trees fitted on Betfair history from 2019 to Feb 2024, which read the same prices better). Which of the smaller changes survive moved when one day was added to the pool (before 17 Nov was rebuilt "all goals lines together" was kept; with it, it was dropped): the small ones are within noise of each other.

### Which side scores next (its own line)

On 49,831 calls of 936 never-seen matches where a goal followed within 60 minutes: version 3 named the right side 61.3% of the time, the market's own split 61.2%, the stronger side before kick-off 59.9% (log loss 0.6529, 0.6530, 0.6604). So it adds almost nothing to the market's own split. (My first run of this test left the market's split out from under the other inputs; it was put right and re-run on the fit days before any unseen day was read.) Kept: moves, game, events; dropped: books, pressing.

### Events, delay, stats

Events collector (af_events.py, plain loop, in watch.list as afevents): live events every 15 s for every linked match, statistics every 60 s for linked matches, line-ups before kick-off; 11 goals matched to a Betfair suspension so far, median 63 s behind it (the old api-football feed 90 s on 12); a red-card or substitution delay is not measured because there are too few. Cap 30,000 calls a day of 75,000 (40,000 left; 552 used by 13:00 UTC). Cards and substitutions are now on 84% of minutes from the events lists of finished matches (4% and 0% before); those lists leave out events cancelled later and I assumed 2 minutes' delay; what the live collector gets on a full day is measured from tonight. Live stats on the scorecard days 21-23 Nov: 44% of minutes have them; 9% of minutes are matches not found on the feed, 14% are matches the feed gives no statistics for (only 153 of 1,247 leagues have them), 33% are minutes of matches the feed had stats for by the end, which we did not have at that minute (not polled in time, or the feed had them late). The ceiling is 77%. The new collector asks for every linked match every minute. Note that the live stats did not improve the signal when tested (pressing: dropped), so more of them is not expected to matter yet.

### What would help that we do not have

- **More weeks of data:** 130 fitted matches gave +13.3 points (LOW + HIGH + late HIGH), 260 +15.1, 521 +18.7, all 1,042 +20.8; each doubling so far added 2 to 4 points, the last one 2. The live model already uses 2,082 matches (28-day window).
- **Faster or fuller live stats:** on the 34,429 minutes where we have them, adding stats changed the points by -0.9 (log loss +0.0009); what FASTER stats would add cannot be estimated from what we have; no purchase proposed.
- **Cards and substitutions for the leagues the feed does not cover:** on the 70,933 minutes where we have them, adding them changed the points by +0.1 (log loss +0.0002): no measurable gain.
- **Line-ups before kick-off:** collected for about half the matches; not yet tried.

### Nightly table, switch, refit

Each night (23:30 UK) the scorecard adds version 3 beside the old signal, 2 and 2b, the best one per day, the rule for switching the trial, and the events delay. Version 3 is always scored by a model fitted before the day (the scorer refuses a day the model was fitted on). The trial still reads version 2 and switches only when a newer version beats it for a full 7 scored days on LOW and on late HIGH (tested on made-up weeks: win, lose, tie, 6 days, too few calls), and only to a version that is running live and, for version 3, whose live numbers agree with its replay (correlation 0.80 or more). At 13:15 UTC today live version 3 and live version 2 did not move together on 82 moments of about 8 small matches (correlation 0.00; the replay has 0.37), so this agreement check is the first thing to read tonight. The weekly refit runs on Mondays from 05:00 UK (a 28-day window) as a plain loop; the live version 3 and 2b run once a minute on paper (goaltrade.v3_scores, v2b_scores).

### Where I departed from my own written rules

- The written rule (v3_criteria.md, 5) judges every change on LOW + HIGH + late HIGH. I judged each question only on its own part (quiet on LOW alone, goal coming on HIGH + late HIGH); that was in the code before any result but not in the written rule.
- The unseen days were unseen by the FITS. They were not unseen by people: earlier sessions reported on them and the order was written from some of them, so the choice of ideas is not blind. Only days from 25 Nov are fully clean.
- The written rule asked for a test that an event cancelled later is known at the time and dropped afterwards. There is no such test; the nightly inputs leave cancelled events out for the whole day, a small piece of hindsight in the quiet model (cards and substitutions).

### Checks (PASS/FAIL)

| # | check | result |
|---|---|---|
| 1 | Old signal, version 2 and the other old files unchanged | PASS: 23 of 25 files match their start-of-session sums; the two that changed are sc_report.py and late_under.py, both backed up first (.bak_s25) and changed only where the order asks |
| 2 | Events collector, plain loop in watch.list, own cap 30,000 | PASS: running, 552 calls used by 13:00 UTC, plan left 68,700 |
| 3 | Delay against the Betfair suspension | PARTIAL: 11 goals so far (median 63 s), grows by itself each night |
| 4 | Share of minutes with live stats before and after | BEFORE PASS; AFTER NOT YET (first full day tonight) |
| 5 | Changes kept by the fixed rule, every change reported | PARTIAL: each question judged on its own part, see above; table above (one question is also tested, in the run log logs/v3_decide.log) |
| 6 | Never-seen days (by the fits) looked at once for the result, after frozen.json | PASS, with the caveat above: logs/v3_eval.log |
| 7 | Known-answer tests | PARTIAL: 48 passed, 0 failed (test_v3.py), late_under tests 30 of 30; the cancelled-event test is missing |
| 8 | Which side, own line | PASS (no edge over the market) |
| 9 | Weekly refit, scorer refuses fitted days | PASS (loop started, test of the refusal in test_v3.py; the first real refit is 30 Nov) |
| 10 | Nightly table keeps working if version 3 files are missing | PASS: tested with no files; the nightly input build was run on 23 Nov and gives the same numbers (5,805 calls, correlation 0.9995) |
| 11 | Trial switch tested both ways; today still version 2 | PASS |
| 12 | Memory under 2 GB a step | PASS for the inputs (1.5 GB peak, 7 Nov) and refit (1.3 GB); the keep-or-drop run itself was not measured |
| 13 | Report, survives the nightly rewrite, pushed | see the commit |

_Other: trial.py (order book trial, not mine) was killed for lack of memory 5 times on 24 Nov 11:04-11:33 server time, before this session started, peaking near 10.9 GB; mine ran only after it. 17 Nov stopped the input builder once (a market with no money figure); it is fixed and rebuilt, and the decision was run again with it. The live version 3 scored nothing from 13:03 to 13:06 UTC (a poll with no new prices broke the number columns; caught by reading the stored rows, fixed, tested)._

What I need from you: nothing.

## Backtest

_Written 24 Nov 2026 (session 23). Tier one, money £0: a scorecard, no bets, no paper. Same code as the nightly scorecard; kept under the nightly table each night. Two depths, kept apart: A = the full signal on the recorded days; B = a price-only version on years of history._

**In one paragraph.** The full signal (version 2) has now been checked on 1,494 matches over the 10 days it never saw (1,780 more on the 15 days it was fitted on, kept separate), and a price-only version on 188,598 matches over 93 months (Jan 2019 - Sep 2026), 56,517 of them in the last 31 months that it never saw. When the full signal says HIGH a goal follows within 10 minutes 23.4% of the time against 21.7% normally (+1.7 points, plausibly +0.5 to +2.8): a small gap that the luck of these matches could nearly explain, above normal on 8 of 10 unseen days but only +1.5 points, plausibly -0.3 to +3.5 on the cleanest data (586 matches, full recording and score feed) and +1.0 points, plausibly -0.1 to +2.2 before minute 85. Its LOW does more: 16.6% against 20.5% (-3.9 points, plausibly -4.9 to -2.8), below normal on 8 of 10 days; about a third of that is the match simply ending (before minute 85: -2.7 points, plausibly -4.1 to -1.3). The price-only version is steadier: HIGH 31% against 23% normal (+7.3 points, plausibly +7.0 to +7.7) and LOW 15% against 23% (-7.7 points, plausibly -8.0 to -7.4) in the never-seen years. It does not come and go: every season lies between +6.9 and +8.9 points for HIGH and -9.6 and -7.1 for LOW, and HIGH was above normal in all 92 months that had HIGH calls. But over a third of its HIGH gap is only that the match was priced for goals (against other matches of the same kind it is +4.6 points, plausibly +4.3 to +5.0), and the over price already said so: on every kind of minute the goals came below what the price implied, HIGH minutes no better than the rest. On the same recorded calls the price-only version is no weaker per call than the full one, it just says HIGH half as often (14% of the time against 26%), and its HIGH there is +5.4 points (feed goals), not the history's +7.3, so take the history as the upper figure. The three findings about missed goals over the long history: (1) 'HIGH only works in the second half' does **not** hold for the price-only version: first half +8.4 (+7.8 to +9.0), second half +6.7 (+6.4 to +7.1), in every season (version 2 on unseen days is still weaker in the first half: 21% against 20% normal, second half 26% against 23%). (2) 'The facts we hold would not have caught them' holds: a one-goal game from minute 70 on NORMAL or LOW minutes scored -2.0 (-2.4 to -1.7) (the same in every season), red cards made no difference, minutes after a substitution scored slightly less; shots and corners are not in the history. (3) 'The over price not drifting lifts them' holds, small at 5 minutes (+0.4 (+0.2 to +0.5)) and about 2 points over 10-15 minutes (+2.1 (+1.8 to +2.4)); a price drifting faster than normal does the opposite (-4.4 (-4.6 to -4.1)). **Verdict: LOW WORKS as a warning of quiet minutes; HIGH NOT YET, as it adds little that the price does not already say. Next test 29 Nov, when the goal-trade rerun is due.**

### A. Every recorded day, version 2 with all its inputs, minute by minute

- **Fitted on these days:** 11-02 (5,856 minutes, 81 matches), 11-03 (5,333 minutes, 73 matches), 11-04 (3,056 minutes, 41 matches), 11-05 (3,100 minutes, 40 matches), 11-06 (363 minutes, 6 matches), 11-07 (4,022 minutes, 55 matches), 11-08 (4,736 minutes, 69 matches), 11-09 (425 minutes, 5 matches), 11-13 (75 minutes, 1 matches), 11-14 (9,383 minutes, 133 matches), 11-15 (6,728 minutes, 89 matches), 11-16 (1,356 minutes, 19 matches), 11-17 (5,867 minutes, 77 matches), 11-18 (551 minutes, 7 matches), 11-19 (1,851 minutes, 23 matches). 10-12 Nov had no training rows. The normal rates were also set on 2-19 Nov. Every other day (31 Oct, 1 Nov, 10-12 and 20-24 Nov) is **never seen**.
- **How:** each minute, only what had arrived by that minute, with each feed's own delay; replays go through the nightly code unchanged. Rebuilt from the recordings, 23 Nov matched the nightly scorecard's own file exactly (221 shared calls, 2 matches, largest difference 0.0). Minutes when the newest football price was over a minute old are dropped, as the live signal does.
- **Goals:** from the score feed where there is one; otherwise read from Betfair's suspensions and price jumps (see below). 'Normal' is the average for the same minutes and scores in the same pool.
- **Thin or missing days (not hidden):** 31 Oct and 1 Nov have no tick recording, only one price a minute, so version 2 ran on part of its inputs there. The football recorder was off about 16:00-18:00 local on 31 Oct. No score feed at all on 10-12 Nov, almost none on 13 and 9 Nov, thin on 16 and 18. 6 Nov has 7 matches in all. 24 Nov has only the overnight matches (5). 8 Nov and 7 Nov have gaps in the football stream: 8,128 and 1,999 calls were dropped there because the newest price was over a minute old. Four late-kick-off matches of 23 Nov are not in the nightly file so are not in its line. 21-23 Nov here include matches without a score feed, so their match counts are larger than the nightly table's, which has feed matches only.

| | matches | calls | HIGH: goal within 10 (range) | normal | NORMAL | LOW: goal within 10 (range) | normal | goals that came in HIGH / NORMAL / LOW | share of time HIGH | warning, min (median) | HIGH spells with no goal |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **Never-seen days, all** | 1,494 | 130,293 | **23%** of 37,357 (22%-25%) | 22% | 23% | **17%** of 30,324 (16%-18%) | 21% | 30% / 48% / 23% of 3,532 | 29% | 10.0 (5.8) | 5,039 of 7,253 (69%) |
| never-seen, full recording (10-12, 20-24 Nov) | 1,034 | 92,912 | **23%** of 22,857 (21%-24%) | 21% | 23% | **16%** of 23,459 (15%-17%) | 21% | 26% / 51% / 22% of 2,486 | 25% | 10.0 (5.8) | 3,246 of 4,598 (71%) |
| never-seen, full recording and score feed (cleanest) | 586 | 53,511 | **23%** of 12,577 (21%-25%) | 21% | 25% | **14%** of 14,208 (13%-16%) | 20% | 26% / 52% / 21% of 1,432 | 24% | 9.1 (5.5) | 1,863 of 2,656 (70%) |
| never-seen, score feed goals | 1,046 | 90,892 | **24%** of 27,077 (22%-25%) | 22% | 24% | **16%** of 21,073 (15%-17%) | 20% | 31% / 47% / 22% of 2,478 | 30% | 9.6 (5.6) | 3,656 of 5,311 (69%) |
| never-seen, goals read from the market | 448 | 39,401 | **22%** of 10,280 (20%-25%) | 22% | 21% | **18%** of 9,251 (16%-20%) | 22% | 26% / 50% / 24% of 1,054 | 26% | 11.3 (6.2) | 1,383 of 1,942 (71%) |
| never-seen, 31 Oct-1 Nov (thin inputs) | 460 | 37,381 | **24%** of 14,500 (23%-26%) | 22% | 23% | **19%** of 6,865 (17%-22%) | 20% | 37% / 40% / 23% of 1,046 | 39% | 10.1 (5.9) | 1,793 of 2,655 (68%) |
| **Fitted days, all (not accuracy)** | 1,780 | 140,616 | **24%** of 34,361 (23%-25%) | 21% | 22% | **16%** of 35,363 (15%-17%) | 20% | 27% / 50% / 23% of 3,860 | 24% | 9.3 (5.7) | 4,847 of 6,976 (69%) |
| fitted, score feed goals | 1,085 | 82,395 | **24%** of 21,507 (23%-26%) | 21% | 22% | **15%** of 20,509 (14%-16%) | 20% | 29% / 49% / 21% of 2,228 | 26% | 10.0 (5.8) | 2,884 of 4,205 (69%) |
| fitted, goals read from the market | 695 | 58,221 | **24%** of 12,854 (22%-26%) | 21% | 22% | **18%** of 14,854 (16%-19%) | 21% | 24% / 51% / 25% of 1,632 | 22% | 8.1 (5.5) | 1,963 of 2,771 (71%) |

Day by day (fitted = version 2 was fitted on that day, so it does not count as accuracy):

| | matches | calls | HIGH: goal within 10 (range) | normal | NORMAL | LOW: goal within 10 (range) | normal | goals that came in HIGH / NORMAL / LOW | share of time HIGH | warning, min (median) | HIGH spells with no goal |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-10-31 never seen (one price a minute, no pre-match price, recorder off 16:00-18:00) | 237 | 17,541 | **25%** of 6,732 (22%-27%) | 22% | 23% | **18%** of 3,195 (15%-21%) | 20% | 39% / 39% / 22% of 491 | 38% | 8.6 (5.4) | 852 of 1,267 (67%) |
| 2026-11-01 never seen (one price a minute, no pre-match price) | 223 | 19,840 | **24%** of 7,768 (22%-27%) | 22% | 24% | **21%** of 3,670 (17%-24%) | 20% | 35% / 41% / 24% of 555 | 39% | 11.4 (6.3) | 941 of 1,388 (68%) |
| 2026-11-02 fitted | 116 | 10,259 | **24%** of 2,636 (20%-29%) | 21% | 25% | **20%** of 2,231 (15%-24%) | 19% | 26% / 51% / 23% of 308 | 26% | 9.5 (5.7) | 350 of 536 (65%) |
| 2026-11-03 fitted | 141 | 12,824 | **21%** of 2,737 (17%-25%) | 21% | 22% | **16%** of 3,268 (12%-19%) | 20% | 24% / 55% / 21% of 333 | 21% | 8.4 (5.6) | 412 of 566 (73%) |
| 2026-11-04 fitted | 108 | 9,856 | **23%** of 1,832 (17%-28%) | 20% | 24% | **18%** of 3,443 (14%-21%) | 20% | 19% / 51% / 31% of 283 | 19% | 9.5 (6.0) | 260 of 366 (71%) |
| 2026-11-05 fitted | 99 | 8,697 | **25%** of 2,599 (21%-29%) | 21% | 23% | **16%** of 2,007 (13%-20%) | 21% | 31% / 48% / 21% of 243 | 30% | 9.4 (5.9) | 348 of 512 (68%) |
| 2026-11-06 fitted | 7 | 599 | **20%** of 157 (4%-30%) | 21% | 30% | **4%** of 220 (1%-10%) | 17% | 25% / 50% / 25% of 12 | 26% | 7.5 (6.0) | 21 of 28 (75%) |
| 2026-11-07 fitted | 229 | 15,340 | **22%** of 3,356 (18%-25%) | 20% | 20% | **16%** of 4,004 (13%-19%) | 20% | 22% / 53% / 25% of 393 | 22% | 7.9 (5.5) | 528 of 735 (72%) |
| 2026-11-08 fitted | 321 | 16,478 | **19%** of 3,836 (15%-22%) | 20% | 19% | **14%** of 4,240 (11%-16%) | 21% | 24% / 49% / 26% of 402 | 23% | 7.4 (4.7) | 630 of 830 (76%) |
| 2026-11-09 fitted | 61 | 5,362 | **23%** of 1,360 (16%-30%) | 20% | 23% | **13%** of 951 (9%-20%) | 21% | 28% / 57% / 15% of 134 | 25% | 8.0 (5.0) | 229 of 312 (73%) |
| 2026-11-10 never seen (no score feed) | 59 | 5,157 | **25%** of 2,139 (18%-31%) | 22% | 23% | **22%** of 740 (16%-28%) | 21% | 39% / 43% / 18% of 152 | 41% | 15.9 (7.5) | 192 of 292 (66%) |
| 2026-11-11 never seen (no score feed) | 82 | 7,205 | **24%** of 2,165 (19%-30%) | 22% | 20% | **19%** of 1,886 (15%-23%) | 22% | 32% / 41% / 27% of 200 | 30% | 12.8 (7.0) | 246 of 350 (70%) |
| 2026-11-12 never seen (no score feed) | 82 | 7,234 | **20%** of 2,588 (17%-25%) | 22% | 18% | **16%** of 1,422 (11%-21%) | 21% | 35% / 45% / 21% of 175 | 36% | 14.9 (8.2) | 296 of 414 (71%) |
| 2026-11-13 fitted | 83 | 7,220 | **29%** of 2,325 (25%-33%) | 21% | 23% | **17%** of 1,566 (13%-21%) | 21% | 38% / 48% / 14% of 214 | 32% | 11.0 (7.0) | 259 of 405 (64%) |
| 2026-11-14 fitted | 226 | 18,987 | **27%** of 5,103 (24%-30%) | 21% | 23% | **17%** of 5,048 (14%-19%) | 20% | 32% / 45% / 23% of 536 | 27% | 11.6 (6.1) | 616 of 935 (66%) |
| 2026-11-15 fitted | 152 | 13,609 | **25%** of 3,255 (21%-29%) | 21% | 22% | **16%** of 3,379 (13%-19%) | 20% | 28% / 50% / 22% of 372 | 24% | 10.0 (5.9) | 445 of 639 (70%) |
| 2026-11-16 fitted | 57 | 4,806 | **28%** of 1,230 (21%-36%) | 21% | 25% | **17%** of 1,117 (11%-23%) | 20% | 25% / 51% / 24% of 158 | 26% | 7.9 (4.7) | 163 of 255 (64%) |
| 2026-11-17 fitted | 97 | 8,992 | **30%** of 2,263 (25%-35%) | 21% | 21% | **19%** of 1,829 (14%-23%) | 20% | 32% / 47% / 21% of 268 | 25% | 8.5 (5.4) | 316 of 491 (64%) |
| 2026-11-18 fitted | 32 | 2,886 | **17%** of 622 (8%-25%) | 21% | 24% | **15%** of 808 (9%-22%) | 20% | 17% / 55% / 28% of 76 | 22% | 8.7 (5.5) | 105 of 134 (78%) |
| 2026-11-19 fitted | 51 | 4,701 | **23%** of 1,050 (16%-30%) | 21% | 24% | **18%** of 1,252 (12%-25%) | 20% | 25% / 50% / 25% of 128 | 22% | 8.0 (5.6) | 165 of 232 (71%) |
| 2026-11-20 never seen | 164 | 14,548 | **22%** of 2,910 (18%-26%) | 21% | 25% | **15%** of 4,304 (13%-18%) | 21% | 21% / 55% / 24% of 382 | 20% | 9.3 (5.7) | 447 of 633 (71%) |
| 2026-11-21 never seen | 328 | 28,780 | **23%** of 6,541 (21%-26%) | 21% | 23% | **16%** of 7,221 (14%-18%) | 21% | 26% / 52% / 23% of 784 | 23% | 7.8 (5.0) | 1,071 of 1,500 (71%) |
| 2026-11-22 never seen | 218 | 20,530 | **24%** of 4,437 (21%-27%) | 21% | 24% | **15%** of 5,583 (13%-17%) | 20% | 25% / 54% / 21% of 550 | 22% | 9.1 (5.5) | 655 of 955 (69%) |
| 2026-11-23 never seen | 96 | 8,971 | **17%** of 1,965 (13%-21%) | 21% | 25% | **14%** of 2,214 (10%-19%) | 20% | 19% / 58% / 23% of 231 | 22% | 8.3 (5.5) | 326 of 430 (76%) |
| 2026-11-24 never seen (overnight matches only) | 5 | 487 | **38%** of 112 (18%-60%) | 21% | 17% | **7%** of 89 (3%-11%) | 19% | 50% / 42% / 8% of 12 | 23% | 6.0 (3.0) | 13 of 24 (54%) |

Never-seen days by part of the match, HIGH / NORMAL / LOW:

| | HIGH | NORMAL | LOW |
|---|---|---|---|
| first half | 21% of 19,571 (avg 20%) | 23% of 33,184 (avg 22%) | 19% of 9,025 (avg 22%) |
| second half | 26% of 17,786 (avg 23%) | 24% of 29,428 (avg 22%) | 16% of 21,299 (avg 20%) |
| level | 21% of 21,770 (avg 21%) | 23% of 31,571 (avg 22%) | 16% of 9,982 (avg 20%) |
| one-goal game | 28% of 9,332 (avg 23%) | 24% of 24,841 (avg 23%) | 17% of 11,782 (avg 22%) |
| two or more apart | 24% of 6,255 (avg 22%) | 23% of 6,200 (avg 21%) | 17% of 8,560 (avg 19%) |
| last 15 min (75+) | 25% of 4,639 (avg 18%) | 23% of 9,059 (avg 18%) | 12% of 13,561 (avg 17%) |

**How reliable are goals read from the market?** (against matches that have both). Only a rough stand-in, so the feed rows are the ones to trust.

- All recorded-tick days except 20 Nov (the reader was tuned on 20 Nov): 1266 matches, 3,440 goals; found 74%, of those it read 77% were goals, right side 95%, every goal of the match right 45%, within 60 s of the true time 97%.
- 20 Nov: 59 matches, 166 goals; found 77%, of those it read 87% were goals, right side 96%, every goal of the match right 51%, within 60 s of the true time 95%.
- 31 Oct-1 Nov (a price a minute): 395 matches, 1,076 goals; found 59%, of those it read 81% were goals, right side 97%, every goal of the match right 31%, within 60 s of the true time 79%, so no market-read goals are used on those two days.
- It blurs both ends: nearly a quarter of the goals it reads are not goals and about a quarter of the real ones are missed, which makes HIGH and LOW look **closer to normal** than they are. The feed-goal rows (+2.0 (+0.7 to +3.4) HIGH, -4.0 (-5.3 to -2.8) LOW) are the cleaner ones; market-read goals gave +0.9 (-1.4 to +3.3) and -3.6 (-5.5 to -1.5).

### B. Years of history, price-only version (Jan 2019 - Sep 2026)

- **What:** last traded prices once a minute in 18 countries' football: match odds and over/under. No money-per-minute, no live stats. Fitted on Jan 2019 - Jul 2021, checked on Aug 2021 - Feb 2024, accuracy on Mar 2024 - Sep 2026. Of 241,276 matches in the files 188,598 could be scored; dropped because not traded in play (under 10 price prints) 17,472; match odds not settled normally (abandoned, extra time or late) 14,220; match odds runners not named 5,761; a goal could not be timed (its market was settled at the end) 4,249; no over/under 0.5 result in the files 3,994; half time settled at an impossible minute 3,910; kick-off not seen at the scheduled time 2,974; no in-play minutes 98. Several of those (an untimeable goal, an abnormal settlement, no in-play trading, an impossible half time) depend on what happened in the match, so the scored set is not every match.
- **Goals:** from the moment each over/under market settled, less 60 seconds. The history ends 30 Sep and our price recording starts 31 Oct, so no day has both. Three checks instead: (1) all 93 months against the api-football goal minutes, 45,248 matches, 116,385 goals: match goal count right 99.9%, goal time within 1 minute 72%, 2 minutes 91%, 5 minutes 98.8%; first half 89% within a minute, second half 60% (the restart time is estimated); scorer's side right 95%. (2) our own score feed, which does overlap (July-September 2026), 1,155 matches linked and 3,193 goals compared: median 0.4 minute late, 74% within 1 minute, 93% within 2, 95% within 5. (3) On recorded days 20-23 Nov the over 2.5 market closed a median 119 s after the third goal's suspension (5th to 95th percentile 63-537 s), against the 60 s allowed, so some history goal times are a minute or more late.
- A goal counts as known to the replay when its market settled, about 1.1 minutes after the goal, as on the live feeds. Calls stop after five goals. The half-time pause is not called.
- **Fit:** the middle third picked version 2's price inputs plus the over price's 10- and 15-minute drift. It ranks minutes better than chance but weakly (0.570 on the newest third, against 0.526 for minute and score alone; 0.5 = a coin).

| | matches | calls | HIGH: goal within 10 (range) | normal | NORMAL | LOW: goal within 10 (range) | normal | goals that came in HIGH / NORMAL / LOW | share of time HIGH | warning, min (median) | HIGH spells with no goal |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Fitted on, Jan 2019 - Jul 2021 | 55,010 | 4,850,765 | **31%** of 361,358 (30%-31%) | 23% | 23% | **15%** of 342,781 (14%-15%) | 22% | 10% / 84% / 6% of 136,561 | 7% | 14.7 (7.0) | 38,225 of 61,374 (62%) |
| Checked on, Aug 2021 - Feb 2024 | 77,071 | 6,912,291 | **31%** of 643,481 (30%-31%) | 23% | 23% | **15%** of 492,198 (15%-15%) | 22% | 12% / 81% / 6% of 195,496 | 9% | 16.0 (7.3) | 61,979 of 100,500 (62%) |
| **Never seen, Mar 2024 - Sep 2026** | 56,517 | 5,128,946 | **31%** of 572,062 (31%-31%) | 23% | 23% | **15%** of 333,550 (15%-15%) | 23% | 15% / 80% / 6% of 146,334 | 11% | 18.1 (8.0) | 48,440 of 79,793 (61%) |

Each season (points above or below the normal rate, range by resampling matches):

| season | part | matches | HIGH goal in 10 | normal | HIGH, points above | LOW goal in 10 | normal | LOW, points below | share of time HIGH | goals in HIGH / NORMAL / LOW | HIGH spells, no goal |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 2018/19 (2019-01 to 2019-06) | fitted on | 11,046 | **31%** | 22% | +8.9 (+8.0 to +9.9) | **14%** | 22% | -8.0 (-8.5 to -7.4) | 7% | 10% / 84% / 6% | 61% |
| 2019/20 (2019-07 to 2020-06) | fitted on | 18,175 | **30%** | 24% | +6.9 (+6.2 to +7.5) | **15%** | 23% | -7.7 (-8.3 to -7.2) | 8% | 11% / 84% / 6% | 62% |
| 2020/21 (2020-07 to 2021-06) | fitted on | 24,834 | **31%** | 23% | +8.0 (+7.4 to +8.5) | **15%** | 22% | -7.1 (-7.4 to -6.7) | 7% | 10% / 83% / 7% | 63% |
| 2021/22 (2021-07 to 2021-07) | fitted on | 955 | **32%** | 25% | +7.6 (+5.4 to +9.8) | **13%** | 23% | -9.3 (-11.5 to -7.0) | 12% | 17% / 79% / 4% | 61% |
| 2021/22 (2021-08 to 2022-06) | checked on | 29,469 | **31%** | 23% | +7.6 (+7.1 to +8.1) | **15%** | 22% | -7.4 (-7.8 to -7.0) | 9% | 11% / 83% / 6% | 62% |
| 2022/23 (2022-07 to 2023-06) | checked on | 29,270 | **31%** | 23% | +7.6 (+7.1 to +8.1) | **15%** | 22% | -7.5 (-7.8 to -7.1) | 9% | 12% / 81% / 7% | 62% |
| 2023/24 (2023-07 to 2024-02) | checked on | 18,332 | **31%** | 23% | +7.2 (+6.6 to +7.7) | **15%** | 23% | -7.3 (-7.8 to -6.8) | 11% | 15% / 79% / 6% | 61% |
| 2023/24 (2024-03 to 2024-06) | never seen | 8,752 | **31%** | 24% | +7.3 (+6.5 to +8.1) | **15%** | 23% | -8.4 (-9.2 to -7.7) | 12% | 16% / 78% / 6% | 60% |
| 2024/25 (2024-07 to 2025-06) | never seen | 25,290 | **31%** | 23% | +7.5 (+7.0 to +8.0) | **15%** | 22% | -7.1 (-7.5 to -6.7) | 10% | 13% / 80% / 6% | 61% |
| 2025/26 (2025-07 to 2026-06) | never seen | 20,327 | **31%** | 24% | +7.0 (+6.5 to +7.6) | **15%** | 23% | -8.1 (-8.6 to -7.5) | 11% | 15% / 80% / 5% | 61% |
| 2026/27 (2026-07 to 2026-09) | never seen | 2,148 | **32%** | 25% | +7.0 (+5.6 to +8.3) | **14%** | 24% | -9.6 (-11.4 to -7.8) | 18% | 23% / 73% / 4% | 57% |

- Steady: the never-seen third matches the fitted and checked thirds (HIGH +7.8 (+7.4 to +8.2), +7.5 (+7.2 to +7.8), +7.3 (+7.0 to +7.7); LOW -7.5 (-7.8 to -7.2), -7.4 (-7.6 to -7.2), -7.7 (-8.0 to -7.4)). It does not come and go. LOW was on the wrong side of normal in 1 of 93 months (a month with few calls).
- **What I checked because it looked good:** goals after HIGH calls come evenly over the next ten minutes, with no spike that would show a late or early goal clock; leaving out calls within 2, 3 or 5 minutes of a goal still leaves HIGH +6.9, +6.4, +5.2 (those are the middle-third figures); before minute 85 HIGH is +6.0 (+5.7 to +6.3) and LOW -5.9 (-6.4 to -5.5) points, so it is not just the match ending.
- **The main catch: 'HIGH' is partly 'a match priced for goals'.** Compared with matches of the same pre-match goal expectation, HIGH is +4.6 (+4.3 to +5.0) and LOW -5.0 (-5.3 to -4.7). On those HIGH minutes the over price implied 37.6% and 30.8% came; on all minutes 29.9% and 23.7%: HIGH is no better against the price than any other minute. (The price-to-10-minutes conversion is rough: it spreads the goals still expected evenly, so read the ratio, not the level.)
- Missed goals: the share of goals that came while it said HIGH is in the table; 80% of goals came on NORMAL minutes.


**The three findings over the long history** (points above or below normal, with range)

| season | part | HIGH, 1st half | HIGH, 2nd half | chasing late (1-goal game from 70) on NORMAL/LOW | over price not drifting 5 min | 10 min | 15 min | over price drifting fast |
|---|---|---|---|---|---|---|---|---|
| 2018/19 | fitted on | +8.1 (+6.6 to +9.6) | +9.6 (+8.4 to +10.6) | -1.6 (-2.4 to -0.7) | +1.8 (+1.3 to +2.3) | +3.8 (+3.2 to +4.4) | +3.6 (+2.9 to +4.2) | -4.3 (-4.8 to -3.8) |
| 2019/20 | fitted on | +6.2 (+5.1 to +7.2) | +7.3 (+6.5 to +8.0) | -1.6 (-2.3 to -1.0) | +0.8 (+0.5 to +1.2) | +2.3 (+1.9 to +2.7) | +2.5 (+2.0 to +2.9) | -4.1 (-4.6 to -3.7) |
| 2020/21 | fitted on | +8.7 (+7.5 to +9.9) | +7.6 (+6.9 to +8.2) | -1.6 (-2.1 to -1.1) | +0.7 (+0.4 to +1.0) | +2.2 (+1.8 to +2.6) | +2.3 (+1.9 to +2.8) | -3.9 (-4.2 to -3.5) |
| 2021/22 | fitted on | +7.7 (+4.0 to +11.3) | +7.5 (+4.8 to +10.4) | -2.7 (-5.1 to +0.3) | -0.9 (-2.2 to +0.6) | +1.7 (-0.3 to +3.6) | +2.7 (+0.7 to +4.8) | -2.9 (-4.9 to -0.6) |
| 2021/22 | checked on | +8.2 (+7.3 to +9.2) | +7.3 (+6.7 to +7.9) | -1.9 (-2.4 to -1.4) | +0.6 (+0.3 to +0.9) | +2.1 (+1.7 to +2.5) | +2.3 (+1.9 to +2.7) | -3.9 (-4.3 to -3.6) |
| 2022/23 | checked on | +8.5 (+7.7 to +9.4) | +7.1 (+6.5 to +7.7) | -1.6 (-2.2 to -1.2) | +0.5 (+0.3 to +0.8) | +1.9 (+1.6 to +2.3) | +2.2 (+1.9 to +2.6) | -4.2 (-4.5 to -3.8) |
| 2023/24 | checked on | +8.1 (+7.1 to +9.1) | +6.7 (+6.0 to +7.4) | -1.8 (-2.4 to -1.3) | +0.2 (-0.1 to +0.5) | +1.8 (+1.4 to +2.3) | +1.8 (+1.3 to +2.3) | -4.2 (-4.6 to -3.7) |
| 2023/24 | never seen | +8.5 (+7.0 to +10.0) | +6.5 (+5.6 to +7.5) | -2.4 (-3.2 to -1.5) | +0.6 (+0.1 to +1.1) | +1.9 (+1.2 to +2.6) | +2.3 (+1.6 to +3.0) | -4.6 (-5.3 to -4.1) |
| 2024/25 | never seen | +8.3 (+7.4 to +9.2) | +7.0 (+6.4 to +7.6) | -1.9 (-2.4 to -1.4) | +0.4 (+0.1 to +0.7) | +1.9 (+1.5 to +2.3) | +2.4 (+2.0 to +2.8) | -4.3 (-4.7 to -4.0) |
| 2025/26 | never seen | +8.5 (+7.6 to +9.4) | +6.3 (+5.7 to +7.0) | -2.0 (-2.6 to -1.4) | +0.2 (-0.0 to +0.6) | +1.4 (+1.0 to +1.9) | +1.7 (+1.3 to +2.2) | -4.3 (-4.7 to -3.9) |
| 2026/27 | never seen | +7.4 (+5.1 to +9.4) | +6.7 (+4.9 to +8.5) | -2.3 (-4.3 to -0.6) | -0.6 (-1.6 to +0.5) | +0.4 (-1.0 to +1.9) | +1.0 (-0.6 to +2.6) | -4.7 (-6.0 to -3.1) |

- **Finding 1 (HIGH only in the second half): does not hold for the price-only version.** Above normal in both halves in every season (table), stronger in the first half. On unseen recorded days version 2 itself is still weaker in the first half (21% against 20% normal; second half 26% against 23%; last 15 minutes 25% against 18%). So the first-half weakness belongs to version 2, not to football. 
- **Finding 2 (facts would not have caught the missed goals): holds.** Chasing late scored less in every season (one of the eleven slices, a single month, has a range that reaches above normal). Red card shown earlier: 23.8% against 24.0% normal (1,918 matches), no difference. Substitution in the last 10 minutes: 23.4% against 24.7% (13,854 matches), slightly **fewer**. Both on 14,261 linked matches of the never-seen third; shots and corners are not in the history so that part is untested.
- **Finding 3 (over price not drifting): holds, small at 5 minutes (not seen in the newest part-season or the one-month 2021 slice), about +2 points over 10-15 in most seasons, and stronger the other way** when the price drifts fast (-4.4 (-4.6 to -4.1), 444,370 calls). It is already one of the price-only inputs, so it is a lift among the calls it did not call HIGH.

### Price-only against the full version, same recorded calls

| calls | version | matches | calls | HIGH goal in 10 | points above | LOW goal in 10 | points below | time HIGH / LOW | goals caught in HIGH | same-size HIGH, points | same-size LOW, points |
|---|---|---|---|---|---|---|---|---|---|---|---|
| unseen | full v2 | 1,494 | 130,293 | 23% | +1.7 (+0.5 to +2.8) | 17% | -3.9 (-4.9 to -2.8) | 29% / 23% | 30% | +1.7 | -3.9 |
| unseen | price only | 1,494 | 130,293 | 25% | +4.2 (+2.2 to +6.1) | 13% | -7.0 (-8.6 to -5.2) | 13% / 6% | 16% | +3.0 | -3.7 |
| unseen, recorded stream (not 31 Oct-1 Nov) | full v2 | 1,034 | 92,912 | 23% | +1.9 (+0.3 to +3.3) | 16% | -4.2 (-5.4 to -3.1) | 25% / 25% | 26% | +1.9 | -4.2 |
| unseen, recorded stream (not 31 Oct-1 Nov) | price only | 1,034 | 92,912 | 24% | +3.3 (+1.2 to +5.3) | 13% | -6.4 (-8.5 to -4.3) | 14% / 6% | 16% | +2.9 | -2.8 |
| unseen stream, over price and pre-match goals both held | full v2 | 1,007 | 60,025 | 22% | +1.2 (-0.4 to +2.8) | 17% | -4.1 (-5.5 to -2.5) | 28% / 16% | 28% | +1.2 | -4.1 |
| unseen stream, over price and pre-match goals both held | price only | 1,007 | 60,025 | 25% | +3.1 (+1.0 to +5.4) | 13% | -7.3 (-9.7 to -4.8) | 17% / 6% | 20% | +2.9 | -3.8 |
| fitted | full v2 | 1,780 | 140,616 | 24% | +3.3 (+2.1 to +4.5) | 16% | -3.8 (-4.8 to -2.9) | 24% / 25% | 27% | +3.3 | -3.8 |
| fitted | price only | 1,780 | 140,616 | 26% | +4.8 (+3.2 to +6.5) | 15% | -5.5 (-7.2 to -3.8) | 15% / 7% | 19% | +4.2 | -4.2 |
| all recorded, feed goals | full v2 | 2,131 | 173,287 | 24% | +2.3 (+1.4 to +3.3) | 16% | -4.1 (-4.9 to -3.2) | 28% / 24% | 30% | +2.3 | -4.1 |
| all recorded, feed goals | price only | 2,131 | 173,287 | 26% | +5.4 (+3.7 to +7.0) | 14% | -5.6 (-7.0 to -4.2) | 13% / 7% | 16% | +3.9 | -3.7 |
| all recorded | full v2 | 3,274 | 270,909 | 24% | +2.5 (+1.6 to +3.3) | 16% | -3.9 (-4.6 to -3.2) | 26% / 24% | 28% | +2.5 | -3.9 |
| all recorded | price only | 3,274 | 270,909 | 25% | +4.5 (+3.2 to +5.8) | 14% | -6.2 (-7.4 to -5.1) | 14% / 7% | 17% | +3.8 | -3.9 |

Plainly: **the price-only version is not weaker per call, it just speaks less often.** On all recorded days it called HIGH 14% of the time (full version 26%) and caught 17% of goals in HIGH (full 28%), but each HIGH call ran +4.5 points above normal (full +2.5) and each LOW -6.2 (full -3.9). Held to the same number of calls the price-only HIGH beats the full version's by 1.3 points (range 0.3 to 2.1), LOW is a tie (-0.0; -0.8 to +0.9). The recorder kept no pre-match over 2.5 price on most days, so the in-play one from the first 4 minutes stands in for it, and no over line after the third goal: price-only is if anything handicapped here.

**How to read the long history:** on the recorded days with score feed goals, price-only's HIGH was +5.4 points above normal against +7.3 over the history. The recorded days are a small sample with thinner inputs and wider mix of leagues, so the history's +7.3 is an upper figure: expect nearer +5 on the matches we record. The full version's extra inputs (money per minute, live stats) have not shown they help: in both the unseen and all-days sets it is no better than price-only per call on HIGH and roughly equal on LOW.

**What has not been tested:** whether any of this can be bought at prices actually on offer (a goal in 10 minutes is a Betfair next-goal or over price, and the over price already holds most of it); the other exchanges and the next-goal, team-goal and half-time markets were not tried here (this is an accuracy check, not a bet). Opposite side: LOW is the better half and is shown beside HIGH everywhere. Nothing here is money: history is last-traded prices.

## Three matches, five minutes at a time

v2 = version 2's chance of a goal in the next 10 minutes; usual rate = how often a goal followed in the same minute band and score on 2-19 Nov (what HIGH / LOW is measured against); old signal = the old model's chance and its band against its own usual level. RIGHT/WRONG marks only HIGH and LOW.

### Best called on 2026-11-27 (69% of 48 HIGH/LOW calls right): Leon v Cruz Azul (live)
Goals (Betfair suspension times): 9' 0-1, 31' 0-2, 68' 0-3, 74' 0-4. On these lines: 6 right, 3 wrong.

| min | score | v2: goal in next 10 min | usual rate | old signal | next 10 min | call |
|---|---|---|---|---|---|---|
| 1 | 0-0 | 12% **LOW** | 20% | none | GOAL 9' (0-1) | WRONG |
| 5 | 0-0 | 21% **NORMAL** | 20% | none | GOAL 9' (0-1) |  |
| 11 | 0-1 | 21% **NORMAL** | 21% | none | no goal |  |
| 15 | 0-1 | 23% **NORMAL** | 21% | none | no goal |  |
| 20 | 0-1 | 21% **NORMAL** | 25% | none | GOAL 31' (0-2) |  |
| 25 | 0-1 | 23% **NORMAL** | 25% | none | GOAL 31' (0-2) |  |
| 30 | 0-1 | 21% **NORMAL** | 25% | none | no goal |  |
| 36 | 0-2 | 22% **NORMAL** | 18% | none | no goal |  |
| 40 | 0-2 | 20% **NORMAL** | 18% | none | no goal |  |
| HT | | | | | | |
| 46 | 0-2 | 24% **NORMAL** | 20% | none | no goal |  |
| 50 | 0-2 | 26% **HIGH** | 20% | none | no goal | WRONG |
| 55 | 0-2 | 24% **NORMAL** | 20% | none | no goal |  |
| 61 | 0-2 | 27% **HIGH** | 19% | none | GOAL 68' (0-3) | RIGHT |
| 65 | 0-2 | 26% **HIGH** | 19% | none | GOAL 68' (0-3), GOAL 74' (0-4) | RIGHT |
| 70 | 0-3 | 11% **LOW** | 19% | none | GOAL 74' (0-4) | WRONG |
| 75 | 0-4 | 11% **LOW** | 19% | none | no goal | RIGHT |
| 81 | 0-4 | 10% **LOW** | 16% | none | no goal | RIGHT |
| 85 | 0-4 | 9% **LOW** | 16% | none | no goal | RIGHT |
| 90 | 0-4 | 7% **LOW** | 16% | none | no goal | RIGHT |

### Worst called on 2026-11-27 (26% of 46 HIGH/LOW calls right): Macarthur FC v Melbourne City (replayed)
Goals (Betfair suspension times): 6' 1-0, 33' 2-0. On these lines: 1 right, 5 wrong.

| min | score | v2: goal in next 10 min | usual rate | old signal | next 10 min | call |
|---|---|---|---|---|---|---|
| 2 | 0-0 | 16% **NORMAL** | 20% | 38% NORMAL | GOAL 6' (1-0) |  |
| 5 | 0-0 | 21% **NORMAL** | 20% | 38% NORMAL | no goal |  |
| 10 | 1-0 | 22% **NORMAL** | 21% | 38% NORMAL | no goal |  |
| 15 | 1-0 | 22% **NORMAL** | 21% | 38% NORMAL | no goal |  |
| 20 | 1-0 | 21% **NORMAL** | 25% | 38% NORMAL | no goal |  |
| 26 | 1-0 | 21% **NORMAL** | 25% | 38% NORMAL | GOAL 33' (2-0) |  |
| 30 | 1-0 | 22% **NORMAL** | 25% | 38% NORMAL | GOAL 33' (2-0) |  |
| 35 | 2-0 | 21% **NORMAL** | 18% | 38% NORMAL | no goal |  |
| 40 | 2-0 | 22% **NORMAL** | 18% | none | no goal |  |
| HT | | | | | | |
| 46 | 2-0 | 26% **HIGH** | 20% | none | no goal | WRONG |
| 50 | 2-0 | 25% **NORMAL** | 20% | none | no goal |  |
| 56 | 2-0 | 27% **HIGH** | 20% | 38% NORMAL | no goal | WRONG |
| 60 | 2-0 | 26% **HIGH** | 20% | 38% NORMAL | no goal | WRONG |
| 65 | 2-0 | 26% **HIGH** | 19% | 38% NORMAL | no goal | WRONG |
| 70 | 2-0 | 28% **HIGH** | 19% | 38% NORMAL | no goal | WRONG |
| 75 | 2-0 | 16% **NORMAL** | 19% | 38% NORMAL | no goal |  |
| 81 | 2-0 | 20% **NORMAL** | 16% | none | no goal |  |
| 85 | 2-0 | 17% **NORMAL** | 16% | none | no goal |  |
| 90 | 2-0 | 8% **LOW** | 16% | none | no goal | RIGHT |

_Built 2026-11-27 23:44 UTC by /root/pe-sports/goaltrade/sc_build.py + sc_report.py (session 22). Scorecard only._
