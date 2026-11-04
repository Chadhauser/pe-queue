# Finder 2026-11-04: candidates C1-C6 on every untouched hold-out (items 55c-58c), and item 73
**Verdict: nothing passes, PASS lines none. None of the six candidates survives out of sample.** Item 73 is a near miss on a proxy, not a tradable line.
Queue fix: commit 238e6d4, "remove duplicate 52-54", also deleted items 55-59 of the overnight section 16 s after they were added, so no lane had run them. Restored as 55c-59c.

## 55c census: what the candidates were not selected on (FTS xlsx: not on the box)
| Source | Holds | Tests |
|---|---|---|
| bf_hist_other OU15, BTTS | 861, 855 markets at first count, 31 Aug-28 Sep 2026; loader 347 still adding (BTTS 929 by the last run); item 59's search predates this | C1, C6, C3 |
| bf_hist_other MATCH_ODDS, OU25 | 16,596 and 13,250 markets, Jul-Sep 2026, Aug-Sep for OU25 | C4, C2 |
| liq_sample | 30 Oct-4 Nov, 1,262 events, real touch; rolls at about 6 days | C1-C5; partly seen by items 36, 37, 45 |
| af_fixtures, af_events | events 2023-2026, La Liga 380 + 109 untouched games; results 2016+ | C1, C6, C2 results |
| fd_matches | 2006-07 on, closing OU2.5 from 2019-20, exchange close from 2024-25 | C1 at HT, C2 |

## 56c C1, C6 La Liga 0-0 (jobs/499_cand_c1c6_laliga.sh; gate 0.973 of 219)
| Line | Source | n | per £10 | t | h1 | h2 |
|---|---|---|---|---|---|---|
| C1 back O1.5 T35 goal +5 | Sep 2026 tape | 10 | -2.726 | -1.47 | -6.72 | -1.73 |
| C1 lay U1.5 T30 goal +8 | Sep 2026 tape | 10 | -2.635 | -1.24 | -10.00 | -0.79 |
| Same, all leagues | Sep 2026 tape | 350, 361 | -0.276, -0.403 | -0.84, -1.28 | -0.10, -0.44 | -0.45, -0.36 |
| C1 back T35, lay T30 | real touch, no halves | 4, 5 | -0.54, +1.06 | | | |

Over 1.5 given 0-0, La Liga v the implied of the selection seasons: T30 implied 0.544, won 2023 0.483 (n 172, z -1.61), 2024 0.575, 2025 0.660, 2026 0.519 (n 52, z -0.35). T35 implied 0.506, won 2023 0.462 (n 156, z -1.10), 2026 0.500 (n 48, z -0.08). C6, the other windows, 2023 and 2026 are z -1.40 to +0.46. HT 0-0 then 2+ goals, SP1: 2006-24 0.412 (n 2,164), selection seasons 0.470 (n 236), and 2025-26's 0.52 is the highest of 21 seasons. The lead was one good season. Forward: tape 10 + touch 4 = 14 at T35, about 4.2 a week, so 20 near 15 Nov and 50 near 3 Jan 2027 ignoring any winter break, but only if something records them, as liq_sample rolls (59c).

## 57c C2 Segunda (jobs/499_cand_c2_segunda.sh)
| Line | Source | n | per £10 | t | h1 | h2 |
|---|---|---|---|---|---|---|
| Lay U2.5 close + 1 tick, PROXY | untouched 2019-24 | 2,310 | +0.111 | 0.40 | +0.43 | -0.37 |
| Same | selection 2024-26 | 924 | +0.941 | 2.49 | +1.14 | +0.74 |
| Lay U2.5 KO, T15 | 2026-27 prints | 64, 65 | -0.542, -0.250 | -0.41, -0.19 | -1.86, -0.97 | +0.77, +0.49 |
| Lay BTTS No KO, T15 | 2026-27 prints | 11, 10 | -4.131, -4.067 | -1.36, -1.35 | -6.29, -6.19 | -1.54, -1.95 |
| Lay U2.5, BTTS No | real touch, no halves | 11, 11 | +0.979, +3.180 | 0.30, 1.21 | | |

Under minus fair, points: 2019-24 +0.4, +1.4, -3.1, +3.6, +2.2; selection -5.3, -3.8; 2026-27 -1.4 (n 131, proxy +0.132). Exchange close only from 2024-25, Pinnacle before, so the sources differ across that split. Selection.

## 58c C3, C4, C5 (jobs/499_cand_c3c4c5.sh; C3 gate 0.984 of 193; first run not scored, gate bug, the one re-run used)
| Line | Source | n | per £10 | t | h1 | h2 |
|---|---|---|---|---|---|---|
| C3 lay BTTS No KO | Sep 2026 prints | 663 | -0.433 | -1.19 | -0.93 | +0.08 |
| C3 lay BTTS No | real touch, 6 days | 931 | -0.998 | -3.37 | -0.29 | -1.71 |
| C4 draw 2-2 FRESH settle, k=1 | Jul-Sep 2026 prints | 529 | -0.389 | -1.09 | +0.05 | -0.84 |
| C4 FRESH settle, k=4 | Jul-Sep 2026 prints | 529 | -0.569 | -1.63 | -0.14 | -1.02 |
| C4 back draw | real touch | 39 | -2.452 | -1.80 | -0.80 | -4.19 |
| C5 lay BTTS Yes 0-0 75'+, fav 2-3 | real touch | 61 | +0.158 | 0.65 | -0.10 | +0.44 |
| C5 all prices | real touch | 100 | +0.182 | 0.82 | +0.09 | +0.27 |

C3 on the selection tape reproduces job 491, n 5,898 +0.265 v 5,891 +0.262; T15 on Sep 2026 n 658 -0.479; 6 of 17 leagues positive in both seasons. The real touch is one week's matchdays, so its t is inflated. C4: won 0.590 v implied 0.606, the market is fair; bands 80 and 85 have 0 and 3 old-goal entries, so CEIL is weak there. C5: Yes won 0.040, lay touch a median 21 v LTP 5.7, far from the bar.

## 73 Within-season goal error (jobs/499_season_goal_persist.sh; 138 league-seasons, 2019-26, rule written first)
| Line | n | per £10 | t | h1 | h2 | League-seasons, positive, t on their means |
|---|---|---|---|---|---|---|
| FOLLOW cut 3 | 17,135 | +0.254 | 3.26 | +0.29 | +0.22 | 72, 0.667, 3.23 |
| FOLLOW cut 5 | 9,060 | +0.328 | 3.07 | +0.23 | +0.39 | 40, 0.700, 3.09 |
| FOLLOW cut 8 | 1,629 | +0.038 | 0.15 | -0.51 | +0.17 | 9, 0.444, 0.28 |
| FADE cut 3, control | 17,135 | -0.063 | -0.76 | +0.04 | -0.14 | 72, 0.514, -0.89 |
| FOLLOW cut 3, cut 5, exchange close only | 4,492, 1,875 | +0.059, +0.215 | 0.38, 0.89 | | | 20, 9 |

Spearman first third v rest 0.173, same sign 0.551; at |error| >= 5 the rest moves +1.31 points the same way. Misses t 3.5, and a close is not a print: a Pinnacle price cannot be laid. Worth one forward test: item 74.

Limits: the tape is LTP only, so print results are upper bounds. Loader 347 is still running, so counts moved between runs. The feed lags: Levante v Atletico shows Over at 1.12 with the feed at 0-0, so an entry can follow an unseen goal. Real-touch results use the local feed, to 4 Nov 08:18. Redirection was refused in this session, so these jobs ran to the console; the runner then ran each committed job itself, and those are the logs in /root/pe-queue-logs (La Liga presets and SURVIVORS agree; all-league n larger as the loader grows, ALL T35 goal +5 n 365 -0.256).
