# Finder 2026-11-05, item 0i: engine patch check, second daily run: nothing passes, 18 alerts v a bar of 300
jobs/499_engine_patch_check.sh, read only, unchanged. Took 374 s (the queue's "about 15 s" is out of date), run on Railway. Window from 3 Nov 19:41 UTC to 5 Nov 01:34 UTC. No log in /root/pe-queue-logs: this session may not write there.

| measure | 4 Nov run | 5 Nov run |
|---|---|---|
| predictions, fixtures | 3,435, 193 | 5,945, 259 |
| fav_price fill, all rows | 46.1% | 51.3% |
| under25_price fill, all rows | 38.1% | 43.6% |
| fav, under25 on recorder-covered rows | 73.9%, 61.0% | 77.6%, 65.9% |
| home_sot fill, all rows | 5.2% | 11.2% |
| home_sot on fixtures goal_stats_live holds | 97.8% (20 fixtures) | 98.4% (33 fixtures) |
| alerts | 8 | 18 |
| real_price on alerts | 2 of 8 | 11 of 18 (61.1%) |
| real_price inside the target band | 0 of 2 | **0 of 11** |
| settled at real_price | n 1, −£10.00 | n 1, −£10.00 |
| settled at recorder back | n 2, −£4.85 | n 2, −£4.85 |

Baseline before the patch: 195,218 predictions, 0.0% on all three fields; 111 alerts, 0.0% real_price. watchlist_id is still NULL on every row. Stored price matches the recorder: fav median difference 0.000, 73.0% within 2%; under25 79.3% within 2%. Stored outcome agrees with ft_score on 7 of 7.

## What matters
**No alert has yet been at a price it asked for.** Every priced alert is outside its band, and all but one are far below it: S14B wants 1.40-1.75 on Over 2.5 and the market was 1.11, 1.15, 1.16, 1.25; S26 wants 1.45-1.70 on Over 3.5 at 3-0 and it was 1.16, 1.16, 2.06; S27 1.45-1.70 v 1.17; S28 1.25-1.45 v 1.06, 1.06, 1.12. Only 2.06 sits above its band. So the strategies' target bands do not describe the market at the moment they fire. A back order inside the band would not have been matched on the 10 below it; the 2.06 would have been matched, and lost. n is small, 11 alerts, but 0 of 11 is not a near thing. For the strategy chat, not a Finder fix.

Only 1 of the 11 priced alerts has settled: the other 10 had no ft_score when the job ran, and 7 of the 18 have one. Settlement is too thin to read.

## Fill below 50% on leagues the recorder covers (brief's test)
Liga de Expansión MX 0.0%, AFC Champions League Elite 0.0%, Premier League (Uganda) 0.0%, League One 31.1%, AFC Champions League Two 45.9%, League Cup 49.0%. Fav fill. Fixtures with no fav at all though the name matched, a naming fix and not an engine fix, as the brief says:
| fixture feed | recorder |
|---|---|
| Nacional Asuncion v Club Sp. San Lorenzo | Nacional (Par) v Sportivo San Lorenzo |
| Venados FC v Monarcas | Venados FC v Club Atletico Morelia |
| Masr v El Geish | ZED FC v El Geish |
| Atletico Paranaense v Vasco DA Gama | Athletico-PR v Vasco Da Gama |
| Oxford United v Reading | Oxford Utd v Reading |
| Borussia Dortmund U19 v Real Betis U19 | Dortmund U19 v Betis Sevilla U19 |
| Al-Rayyan SC v Al-Nahda | Al Rayyan v Al Nahdha |
| RB Leipzig v Manchester City | RB Leipzig v Man City |
| Buriram United v Kashima | Buriram Utd v Kashima |
| Slavia Praha v Arsenal | Slavia Prague v Arsenal |
| KCCA v Maroons | Kampala City Council v Maroons FC |

Short forms of big clubs (Oxford Utd, Man City, Buriram Utd) and renamed clubs are the pattern. 85 of 259 fixtures have no recorder event by the job's strict match, mostly reserve, non-league and minor leagues the recorder may not hold; two are near misses (Ghazl El Mehalla, Victoria United).

## Verdict
Nothing passes; n is 18 at most. Runs left: 6 and 7 Nov. Survivors: none. GOAL_SIGNAL_LIVE.txt not touched.
