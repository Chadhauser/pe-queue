# Finder 2026-11-04 — item 49: stats-led in-play (what the shots actually predict). PILOT

**Data.** goal_stats_live x goal_timeline x liq_sample. Job: jobs/489_stats_led_inplay.sh (number shared, as 450-499 is full). Fit 3–29 Oct, 15,979 stats rows, 558 fixtures, no prices needed. Scored 30 Oct–3 Nov, 5,104 rows, 167 fixtures; the two windows do not overlap. Priced at the real touch: 1,806 rows, 114 fixtures. The item said first half v second half of the date range, but the recorder only starts on 30 Oct, so this split fits on more data and keeps the fit clean.

**Not tested.** 0-0 and total >= 4: no next line (OU05 not recorded; 1,573 rows). Pre-match price as a feature: the recorder holds none for the fit window. Next goal +8 as an exit: the next goal passes the line, so it equals settle. 34 of 167 fixtures did not map to a recorder game (1,036 rows); 260 rows skipped because stats and timeline disagreed on the score.

**What the stats predict, on the priced rows**

| Predictor | Target | Mean p | Actual | AUC | Brier |
|---|---|---|---|---|---|
| Market, flat goal rate | goal in 10 min | 0.296 | 0.205 | 0.550 | 0.1704 |
| Logistic | goal in 10 min | 0.267 | 0.205 | 0.525 | 0.1677 |
| GBM | goal in 10 min | 0.276 | 0.205 | 0.541 | 0.1675 |
| Market | goal by FT | 0.693 | 0.606 | 0.783 | 0.1883 |
| Logistic | goal by FT | 0.716 | 0.606 | 0.785 | 0.1956 |
| GBM | goal by FT | 0.729 | 0.606 | 0.777 | 0.1979 |

Stats rank goals in the next 10 minutes barely better than chance (all scoring rows: GBM AUC 0.557, top decile 35.8% v bottom 17.0%). On priced rows the market ranks as well or better. The market's 10-minute figure is my flat-rate conversion, so its Brier score there is not a fair comparison.

**Controls, every priced row, spaced 15 min, per £10.** Back P10 n 430 −1.039 t −4.11 h1 −1.02 h2 −1.06; back settle −1.677 t −4.82; lay P10 −0.985 t −3.46; lay settle +3.437 t 2.68, tc 1.02, h1 +0.90 h2 +5.91. Mean lay/back spread 1.121.

**Top 15 by t. Survivors: none; largest line n 100.** (P10 = exit at +10 min; tc = per fixture)

| Model target | Side | Exit | Margin | Sel | n | Games | Price | Per £10 | t | tc | h1 | h2 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Logistic FT | Lay | Settle | .10 | all | 35 | 26 | 1.51 | +11.88 | 2.49 | 1.48 | +10.64 | +12.81 |
| GBM P10 | Lay | Settle | .10 | all | 80 | 60 | 1.18 | +8.24 | 1.96 | 1.34 | +1.90 | +14.91 |
| Logistic FT | Lay | P10 | .15 | first | 10 | 10 | 1.58 | +2.93 | 1.93 | 1.93 | +4.71 | +1.14 |
| Logistic FT | Lay | P10 | .15 | all | 10 | 10 | 1.58 | +2.93 | 1.93 | 1.93 | +4.71 | +1.14 |
| Logistic FT | Lay | Settle | .10 | first | 26 | 26 | 1.50 | +8.65 | 1.53 | 1.53 | +6.81 | +10.00 |
| GBM P10 | Lay | Settle | .10 | first | 60 | 60 | 1.16 | +6.64 | 1.37 | 1.37 | +2.70 | +10.84 |
| Logistic P10 | Lay | Settle | .10 | all | 85 | 54 | 1.35 | +5.23 | 1.35 | 0.50 | −3.04 | +12.93 |
| Logistic FT | Lay | Settle | .15 | first | 10 | 10 | 1.58 | +5.63 | 1.30 | 1.30 | +6.46 | +4.81 |
| Logistic FT | Lay | Settle | .15 | all | 10 | 10 | 1.58 | +5.63 | 1.30 | 1.30 | +6.46 | +4.81 |
| GBM P10 | Lay | Settle | .15 | first | 21 | 21 | 1.11 | +10.45 | 1.24 | 1.24 | +5.13 | +15.29 |
| GBM P10 | Lay | Settle | .15 | all | 23 | 21 | 1.11 | +8.67 | 1.12 | 1.24 | +3.75 | +13.18 |
| Logistic P10 | Lay | Settle | .15 | all | 15 | 12 | 1.27 | +9.37 | 1.04 | 0.89 | +4.61 | +18.89 |
| Logistic P10 | Lay | Settle | .15 | first | 12 | 12 | 1.20 | +10.43 | 0.93 | 0.93 | +5.78 | +19.72 |
| Logistic P10 | Lay | Settle | .10 | first | 54 | 54 | 1.30 | +2.27 | 0.47 | 0.47 | −2.93 | +6.75 |
| Logistic P10 | Back | P10 | .20 | first | 17 | 17 | 10.36 | −10.00 | 0.00 | 0.00 | −10.00 | −10.00 |

**Verdict: nothing passes, pilot.** 0 of 68 lines; no line is near n 300. Do not read the lay settle lines as a lead: at £10 liability, a lay near 1.10 pays about £100 when it wins, so a few results carry the mean. A wrong final score in the feed would also land here, as about 2% of feed goals are phantom (item 0g). Neither effect was measured by this job, and the control's clustered t is only 1.02. Backs at about 10 (late in the game, no exit before the end) lost all 34 entries at margin .15.

**Re-run.** The item asks for a weekly re-run, but it would not help: liq_sample rolls at about 5–6 days, so n stops near 100 per line at about 103 spaced rows a day. It needs retention raised or the entry touches saved (Peter or the strategy chat, as for item 28). No re-run queued.

**Caveats.** The runner also runs this job by itself. Lines were reported whole, not chosen. Log read from the task output, not /root/pe-queue-logs.
