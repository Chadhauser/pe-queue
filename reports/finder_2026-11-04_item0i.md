# Finder 2026-11-04, item 0i: engine patch check, first of the daily runs

**Data:** goal_live_predictions 3 Nov 19:41 to 4 Nov 16:44 UTC, 3,435 rows, 193 fixtures; goal_alerts 8; liq_sample 152 events; goal_timeline for names, as `watchlist_id` is NULL on every row of the window. Job: jobs/499_engine_patch_check.sh, read only. Log: not saved, as /root/pe-queue-logs is outside this session's permitted paths; re-run the job to reproduce (about 15 s).

## Fill rates
| | Before the patch (27 Oct to 3 Nov 19:41) | Since the patch | On fixtures the recorder covers |
|---|---|---|---|
| fav_price | 0.0% of 195,218 | 46.1% | 73.9% |
| under25_price | 0.0% | 38.1% | 61.0% |
| home_sot | 0.0% | 5.2% | 97.8% where goal_stats_live has the fixture |
| stats_source = goal_stats_live | | 4.0% | |
| alerts with real_price | 0.0% of 111 | 25.0% (2 of 8) | |

- The patch works: prices and stats now arrive. Recorder coverage is 126 of 193 fixtures by a strict name match, so it is understated.
- Low SOT is feed coverage, not a fault: goal_stats_live holds 20 of the 193 fixtures. No fixture outside those 20 has SOT.
- Stored prices agree with the recorder: sample of 600 rows, median difference 0.000 on both fav (n 595) and under25 (n 493). About a quarter differ by more than 2% (fav 25.5%, under25 21.7%); not resolved whether that is timing inside the 90 s window or something else.

## Leagues under 50% on covered rows
Premier League (Uganda, 2 covered fixtures, not England) 0.0%, AFC Champions League Elite 0.0%, League Cup (Egypt among them) 8.5%, Division Profesional Clausura 16.7%, AFC Champions League Two 41.2%, and 3. liga CFL A 0.0% on a single row. National League South sits at exactly 50.0%; UEFA Youth League 54.5%, UEFA Champions League 62.2%, Championship 85.2%.

## Naming fix list: recorder has the game, engine stored no price (0% fill, by rows)
Nacional Asuncion v Club Sp. San Lorenzo = Nacional (Par) v Sportivo San Lorenzo | Masr v El Geish = ZED FC v El Geish | Borussia Dortmund U19 v Real Betis U19 = Dortmund U19 v Betis Sevilla U19 | Buriram United v Kashima = Buriram Utd v Kashima | RB Leipzig U19 v Manchester City U19 = RB Leipzig U19 v Man City U19 | Chelsea U19 v Flora III = Chelsea U19 v Tallinna FC Flora U19 | Zanaco v Man Utd Zambia Academy = Zanaco FC v MUZA FC | Crvena Zvezda U18 v Bravo U19 = FK Crvena Zvezda U19 v NK Bravo U19 | KCCA v Maroons = Kampala City Council v Maroons FC | Kataka v URA = Kataka FC v Uganda Revenue Authority | København U19 v Dinamo Tbilisi U19 = FC Copenhagen U19 v Dinamo Tbilisi U19 | Al-Rayyan SC v Al-Nahda = Al Rayyan v Al Nahdha | Sheriff U19 v FCV Farul U19 = Sheriff Tiraspol U19 v FC Farul Constanta U19 | Aberdeen U21 v Queen's Park = Aberdeen B v Queens Park | Formartine United v Cove Rangers = Formartine Utd v Cove Rangers | Comerciantes Unidos v ADT = Comerciantes Unidos v Asociacion Deportiva Tarma | Preston v Sheffield Utd = Preston v Sheff Utd | Farnborough v Ebbsfleet United = Farnborough FC v Ebbsfleet Utd | Manchester United v AS Roma = Man Utd v Roma | Airdrie United v Elgin City = Airdrieonians v Elgin City FC.

The strict match also misses real pairs, such as Ghazl El Mehalla v Al Ittihad = Ghazl El Mahallah v Al Ittihad (EGY) and OFK Beograd U19 v TSC U19 = OFK Belgrade U19 v TSC Backa Topola U19.

## Alerts, every one
| id | Fixture | Alert | Band | real_price | Recorder back | FT | Why no price / P&L per £10 |
|---|---|---|---|---|---|---|---|
| 4800 | Birmingham v Millwall | Over 3.5 at 3-0 | 1.45-1.70 | 2.06 | 2.06 | 3-0 | priced, −£10.00 |
| 4801 | Atletico Madrid v Bayern München | Under 3.5 at 0-0 | 1.25-1.45 | none | 1.04 | 0-2 | **name fix** (Munich); +£0.29 at the recorder price, a 1.03 fill |
| 4802 | Bodo/Glimt v Lille | Under 3.5 at 0-0 | 1.25-1.45 | none | none (lay 1.01) | 0-0 | no back at the touch |
| 4803 | Feyenoord v Inter | Over 2.5 at 0-2 | 1.35-1.55 | none | none | 3-1 | **recorder gap** |
| 4804 | Lask Linz v Slovan Bratislava | Over 3.5 at 3-0 | 1.45-1.70 | none | none | 4-0 | **recorder gap** |
| 4805 | Manchester United v AS Roma | Over 2.5 at 0-2 | 1.35-1.55 | none | none | 3-2 | **recorder gap** |
| 4806 | Villarreal v Paris Saint Germain | Over 4.5 at 0-4 | 1.40-1.75 | none | line not recorded | 0-6 | Over 4.5 is not on the recorder |
| 4809 | Rennes v Olympiakos Piraeus | Under 3.5 at 0-0 | 1.25-1.45 | 1.06 | 1.06 | open | unsettled |

- **Naming fixes will not close the alert gap.** Of 6 unpriced alerts, 1 is a name, 3 are recorder gaps, 1 has no back price and 1 is an unrecorded line. In the recorder gaps the event's other markets are sampled every minute, but the wanted line has no row in the 10 minutes either side (checked by query for 4803, 4804, 4805). Why is not established.
- **Neither priced alert was inside its band:** 2.06 v 1.45-1.70, 1.06 v 1.25-1.45. Item 00 found 7% in band, so these bands still do not describe the market. Under 3.5 at HT 0-0 traded at 1.04 and 1.06 against a band of 1.25-1.45.
- real_price was 7 s and 61 s before sent_at, so no look-ahead on these two. Stored outcomes agree with ft_score on 7 of 7.

## Settlement (item 00's rule: real_price less one tick, £10 back, 2% commission)
| Line | n | Per £10 | Note |
|---|---|---|---|
| real_price as stored | 1 | −£10.00 | S26 only |
| Recorder price by this job's own match | 2 | −£4.85 | S26 −£10.00, S28 +£0.29 |

## Verdict
**Nothing passes; the sample cannot reach the bar** (8 alerts against n >= 300), and these figures say nothing about the strategies' edge. GOAL_SIGNAL_LIVE.txt was not touched. The engine patch is confirmed working on predictions. Needing Peter or the strategy chat, since this box's Finder may not edit the engine or recorder: the naming list above, and why the recorder drops the line an alert wants. Next run 5 Nov, last 7 Nov.
