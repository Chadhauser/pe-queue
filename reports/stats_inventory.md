# Facts about matches and runners on this server, against our recorded prices (builder session 4, 20 Nov 2026)

Our recorded real prices: 31 Oct to 19 Nov 2026. Football: 2,341 matches (13,947 markets) from 2 Nov; British and Irish racing: 449 win markets.
"Joins" = how many of OUR recorded matches or markets the source can be linked to by one keyed link (facts.py, prematch.py, racing_facts.py;
links in grid/cache/fact_links.csv). "Late" = how long after the market itself suspended for a goal the source showed the new score
(median and 90th percentile, measured on the price tape); a fact that arrives after the price has moved is worth nothing for that event.

## In play, football (live collectors)
| Source | What it holds | First - last | Rows | Joins to our matches | How late |
|---|---|---|---|---|---|
| sofascore (ip_stats) | score, minute, expected goals, shots, on target, possession, dangerous attacks, corners | 22 Oct - 9 Nov (stopped) | 39,623 | 453 (it carries the Betfair market id; 294 both names agree, 159 one name, 25 rejected) | 2.7 min median, 5.7 p90; polled every 143 s |
| espn (espn_stats) | score, clock, shots, on target, possession, corners, fouls | 25 Oct - 15 Nov (stopped) | 62,905 | 268 (market id; 31 rejected) | 1.6 min, 5.6 p90; every 74 s |
| api-football stats (goal_stats_live) | score, minute, shots, on target, dangerous attacks, corners, possession | 3 Oct - 20 Nov (running, thin: 4-51 matches a day after 8 Nov) | 27,125 | 113 of 247 | 2.4 min, 4.0 p90; every 181 s |
| goal model inputs (goal_live_predictions) | score, minute, on target, dangerous attacks, RED CARDS, expected goals (only 0.5% of rows) | 6 Jul - 20 Nov (running) | 2,366,508 | 720 of 3,538; 11 of them with a red card | 1.75 min, 8.0 p90; every 66 s |
| api-football scores (goal_timeline) | score, minute, status, team and league names | 7 Jul - 20 Nov (running; almost nothing 10-13 Nov) | 3,371,080 | 724 of 3,695 (572 same names, 97 spelling, 55 hand alias, 0 ambiguous) | 1.3 min, 7.6 p90; every 65 s |
| goal_match_stats / goal_xg_predictions | half-time and full-time snapshots (expected goals, shots in the box, attacks) | Jun - 8 Nov | 1,260 / 3,593 | 56 / 62 (half-time only) | snapshot at half time |
| state_snap, goal_events | minute-by-minute state and goal moments built from goal_timeline | Jul - 9 Nov | 397,265 / 113,281 | 319 (same fixture ids) | same feed as goal_timeline |
| af_events (api-football, fetched after the match) | goals, yellow and red cards (115 reds since 31 Oct), substitutions, by match minute | 2016 - 20 Nov | 1,504,779 | 519 fixtures fetched since 31 Oct | known only after full time: not usable live |
| tb_match_events | score and odds snapshots | May - 20 Nov | 46,419 | 0 (its fixture ids belong to tb_fixtures, which stop 31 May) | - |
| liq_goal_depth, ip_reopen | our own suspension / goal moments taken from prices | Oct - 20 Nov | 781,039 / 321,725 | 1,277 markets | price, not a fact |
| live_signals | a strategy's signals and results, not facts | May - 8 Nov | 3,321 | - | - |
| sofascore_feed | empty | - | 0 | 0 | - |

## Before the start, football
| Source | What it holds | First - last | Rows | Joins to our matches | How late |
|---|---|---|---|---|---|
| af_fixtures + af_stats (api-football) | results of 29 leagues; expected goals per match from 2023; shots, on target | 2016 - 20 Nov 2026 | 103,500 finished matches | 199 of the 333 played in our window (406 markets: match result, over/under, both teams to score) | a result is used only from the day after its kick-off |
| fd_matches (football-data) | results, shots, on target, corners, cards, bookmaker and Pinnacle closing prices, 20 divisions | 2006 - 16 Nov 2026 | 149,763 | 129 of 272 (1-20 Nov) | results arrive within ~a week (most divisions stop 8 Nov) |
| football_matches (football-data, incl. Betfair closing prices 2025/26) | the eight seasons of results and pre-match prices | 1993 - 24 May 2026 | 216,418 | 0 (ends in May): history only | - |
| FTS files (fts_advanced_results, fts_matches, fts_newmodel, fts_ultimate) | form, ratings, model prices, pre-match and in-play prices | 2020 - 7 Oct 2026 | 47,927 / 22,624 | 0 (end before our prices) | - |
| fts_live | FTS early and closing prices, results | 22 Aug - 9 Nov | 1,903 | 157 of 262 | prices, not facts |
| understat (matches, shots) | expected goals per match and per shot | Mar 2024 - 24 May 2026 | 3,476 / 87,165 | 0 (ends in May) | - |
| elo_ratings | one snapshot of 769 teams | 11 Apr 2026 only | 1,198 | not used: stale; Elo is rebuilt from af_fixtures instead | - |
| hist_fixtures / hist_goals | api-football goal minutes | 2024 - 11 Nov 2026 | 15,047 / 39,899 | 0 of 16 since 1 Nov | - |
| match_events, match_shots, match_shots_rich | events and shots per match | to May 2026 | 76,444 / 21,462 / 2,173 | 0 | - |
| team_profiles, referee_stats, upcoming_referees | averages with no date / referees with no match link | undated | 927 / 225 / 0 | not used: cannot tell what was known when | - |
| team news / line-ups (af_lineups) | starting line-ups | fetched after the match (890 fixtures) | 37,171 | not usable before the start | - |

## Racing, tennis, cricket, golf
| Source | What it holds | First - last | Rows | Joins to our markets | How late |
|---|---|---|---|---|---|
| racecards_today | runner, draw, jockey, trainer, going, distance, rating, bookmaker odds | 11 May - 9 Nov (stopped) | 72,215 | 212 of 449 British and Irish win markets (all of 31 Oct - 9 Nov, none after) | fetched about 07:30 on race day, before the first race |
| runners (results) | stall, place, jockey, trainer, starting price | 2022 - 8 Nov | 324,102 | history for draw by course and distance, 14-day jockey and trainer form, course-and-distance winners: 1,881 of our runners on 7 days (draw known 620, jockey form 1,630) | earlier dates only |
| racing_form_features | form features per runner | 2024 - 17 Sep 2026 | 203,365 | 0 (ends before our prices) | - |
| racing_results, racing_bsp, bfsp_history | results and starting prices | to 8 Nov | 22,956 / 245,305 / 408,918 | results and prices, not facts before the off | - |
| jockey_stats, trainer_stats, jockey_course | summary tables, no dates | undated | 302 / 355 / 2,185 | not used: could hold later results | - |
| greyhound_racecards_today | trap, form, trainer, run times | May - 9 Nov | 51,318 | 0: no greyhound market is recorded | - |
| tennis_results_2026, sackmann, tennis_matches, wta_matches | results, ranks, serve numbers per match | to 25 Sep 2026 (latest) | 66,310 and older | not joined: our tennis markets name players by surname only, ranks 2 months old; no live score at all | - |
| cricket_matches_today, cricket_matches, ipl_matches | match list and results | to 21 Oct 2026 (today feed) | 19 / 7,862 / 21,458 | 0 of our cricket markets (feed stopped) | - |
| golf_leaderboards_today | position, score, round scores | 12 May - 9 Nov (5 events since 1 Nov) | 6,707 | not joined: one fetch per event (all rows within 10 s), so no running leaderboard | - |

## What this means
- Expected goals live: 456 of our matches (sofascore 2-9 Nov, plus a few api-football). Shots on target live: 609 matches. Nearly all on 2-9 and 14-15 Nov.
- Every live feed is 1.3 to 2.7 minutes behind the market on a goal (median), so none of them can be used to react to a goal; they are used
  as a running record of the match (who is creating chances), seen only as our server received it: strictly before the order, plus 5 s.
- Measured against the price tape on goals only; for shots and expected goals there is no market event to measure against, so the same feed's goal delay is the best estimate.

## Ways decided by these facts: first results (one test, 31 Oct - 19 Nov, league run 20 Nov 19:50 UTC)
720 ways added (registry ids 52857-53576), every one tested on every day, 0 errors. 2 pass the bar, 139 lean (profit in both halves, under 300 orders).
Honesty check (robust.py): each good row's orders re-run, then its best day and its three biggest winning orders removed. Full table: grid/robust_s4.md.

| Way | Orders | £ | Without best day | Without 3 biggest winners | Without both | In plain words |
|---|---|---|---|---|---|---|
| 53484 | 303 | 1,626 | 900 | -492 | -1,217 | PASSES on paper, but it is long shots: three winners carry it. Racing: back 0-10% chances 10 min before, horses that ran at the course without winning there |
| 53489 | 546 | 1,247 | 331 | -539 | -407 | PASSES on paper, same flaw. Racing: back 0-10% chances 10 min before, on good or firmer going |
| 53109 | 121 | 1,216 | 718 | 631 | 660 | Lean, survives: minute 30, level, both sides together on 0.6 expected goals or fewer: lay the over, hold |
| 53111 | 157 | 1,163 | 710 | 579 | 653 | Lean, survives: the same at 1.0 expected goals or fewer |
| 53238 | 52 | 1,186 | 573 | 512 | 573 | Lean, survives (few orders): minute 30, the over needs two more goals, chances running at 1.5 expected goals a game or fewer: lay the over |
| 53123 | 93 | 605 | 319 | 224 | 244 | Lean, survives: minute 45, level, 1.0 expected goals or fewer: lay the over |
| 53075 | 64 | 966 | 619 | 275 | 222 | Lean, survives: minute 70, level, back the side ahead on shots on target by 2 or more, close a minute after the next goal |
| 52922 | 50 | 315 | 201 | 228 | 145 | Lean, survives: minute 30, level, one side ahead on target by 2 or more: lay the draw, hold |
| 53566 | 53 | 341 | 166 | 248 | 135 | Lean, survives: way 1134 (lay a 30-40% team mid-match) only where that team is level or ahead on shots on target |
| 53117 | 229 | 754 | 448 | 140 | -9 | Lean, does NOT survive: minute 30, level, 3 shots on target or fewer: lay the over |

What knowing the match does to the price-only ways (way: base kept per £100 -> with the fact): lay the draw at kick-off (173, +0.93 on 587 orders)
-> +9.4 where the fair price says the draw is not overpriced (44 orders), +3.8 where it is (47): both better, too few to tell. The same lay at
minute 15: +23 where one side leads on target by 2+ (12 orders), -3.9 where neither does (124). Way 1134 (+3.6): +14.6 where the laid team is level
or ahead on target (53), +4.0 where behind (21). Way 1401 (+0.8): +5.7 when few shots on target (52), -4.6 when many (19). Way 479 (+2.9): -7.8 when
few shots on target (82). Fair price before the start: 180 ways, 8,840 orders, -£84,092 a month together, as the model check predicts (the closing
market is more accurate than the model every year). None of these is money: three weeks, mostly 2-9 Nov, counts far under 300.
