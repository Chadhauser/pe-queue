# Finder 2026-11-04 — item 50: pre-match closing-line residuals

**Data.** af_price_map x bf_hist_price x af_fixtures, 12,255 games mapped. Job: jobs/489_prematch_residuals.sh (number shared, as 450-499 is full; first run crashed on a merge error, fixed once). Fit season 2024: 58,278 prints, 5,792 games. Scored season 2025: 64,287 prints, 6,313 games, split at 20 Dec 2025. Entry as job 472: first real print in tape minutes 0..2, one tick adverse, 2% commission, £10 risk, held to settle.

**Not tested: half of the item.** The tape has no pre-kick-off rows and minute 0 is about 2 min after kick-off. So "line movement from first print to KO" and "does the pre-match move continue in-play" cannot be run here. Only the just-after-kick-off price is tested. stream_ticks and liq_sample do hold pre-match prices, but for days only.

**Split warning.** Seasons overlap in calendar time: 31% of 2024-season prints are later than the first 2025-season print, because leagues run on different calendars. Within one league the seasons do not overlap, but this is a season split, not a strict time split.

**Methods.** A: cells (selection x state x side) chosen on 2024 at n >= 100, mean > 0, t >= 2; states are league, day, kick-off hour, favourite band, overround, Over 2.5 band, and league/hour/day x favourite. 26 cells chosen. B: GBM per selection, outcome − 1/price, margin 5/10/20%.

**Top 15 by t, n >= 300, on 2025. Survivors: none.** tc = per game; x3 = three ticks adverse; ex-top = mean without the largest win.

| Method | Line | Side | n | Games | Price | Mean | t | tc | h1 | h2 | x3 | ex-top |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| A all | hour x favourite, 3 cells | Back | 463 | 169 | 1.63 | +0.475 | 1.32 | 0.90 | +0.405 | +0.538 | +0.325 | +0.436 |
| B | Under 1.5, .20 | Lay | 421 | 421 | 6.80 | +0.237 | 1.06 | 1.06 | +0.280 | +0.201 | +0.142 | +0.223 |
| B all | all, .20 | Back | 2,546 | 2,066 | 4.66 | +0.382 | 0.98 | 0.44 | −0.456 | +1.392 | +0.052 | +0.279 |
| A all | league x favourite, 3 cells | Back | 331 | 229 | 2.45 | +0.667 | 0.97 | 0.89 | +0.877 | +0.537 | +0.443 | +0.508 |
| B | Over 3.5, .05 | Lay | 2,409 | 2,409 | 3.93 | +0.112 | 0.91 | 0.91 | −0.025 | +0.243 | 0.000 | +0.105 |
| B all | all, .20 | Lay | 2,327 | 1,825 | 4.59 | +0.125 | 0.89 | 0.78 | −0.126 | +0.403 | +0.016 | +0.111 |
| B | Under 2.5, .05 | Lay | 1,603 | 1,603 | 2.31 | +0.203 | 0.87 | 0.87 | −0.100 | +0.509 | +0.064 | +0.186 |
| B | Under 1.5, .10 | Back | 1,422 | 1,422 | 4.32 | +0.396 | 0.84 | 0.84 | +0.393 | +0.398 | +0.074 | +0.272 |
| B | Draw, .20 | Back | 405 | 405 | 4.61 | +0.689 | 0.72 | 0.72 | −1.648 | +3.182 | +0.309 | +0.473 |
| B | Over 2.5, .10 | Lay | 496 | 496 | 2.06 | +0.282 | 0.63 | 0.63 | −0.270 | +0.838 | +0.133 | +0.236 |
| B | Under 3.5, .05 | Back | 1,037 | 1,037 | 1.49 | +0.133 | 0.62 | 0.62 | −0.032 | +0.295 | −0.007 | +0.105 |
| B | Under 1.5, .20 | Back | 608 | 608 | 4.76 | +0.478 | 0.62 | 0.62 | −0.595 | +1.516 | +0.142 | +0.188 |
| A all | league x favourite, 5 cells | Lay | 652 | 553 | 3.08 | +0.234 | 0.59 | 0.55 | +0.391 | +0.121 | +0.051 | +0.155 |
| B | Over 2.5, .05 | Lay | 1,301 | 1,301 | 2.03 | +0.168 | 0.59 | 0.59 | +0.025 | +0.302 | +0.014 | +0.136 |
| B | FH Over 1.5, .05 | Back | 896 | 896 | 2.80 | +0.250 | 0.57 | 0.57 | −0.151 | +0.633 | +0.048 | +0.208 |

**League error persistence, one thing worth carrying forward.** Spearman of mean(outcome − 1/price) by league, 2024 v 2025, n >= 100 each: Under 2.5 0.55 (p 0.022, 17 leagues), Over 2.5 0.49 (p 0.047), BTTS Yes 0.57 (p 0.027, 15), Over 3.5 0.45, Under 3.5 0.41, Over 1.5 0.37, Under 1.5 0.38, FH Over 1.5 0.27, BTTS No 0.18; Match Odds about zero (home 0.14, away −0.07, draw −0.04). Goal lines look persistent and Match Odds does not. That is 12 related tests with no correction, on few leagues, and the goal lines share the same goals, so treat it as a reason to run item 52, not a result. Trading it failed here: league cells chosen on 2024 lost (back, 2 cells, n 664, −£0.952, t −1.66).

**Verdict: nothing passes** on the part that can be tested. 0 of 113 lines, best t 1.32 (Bonferroni about 3.51). Cells chosen on 2024 made +£1.86 there and +£0.05 on 2025, which is what picking noise looks like. GBM lines made +£1.2 to +£8.6 in-sample and about zero on 2025. Entry is LTP, so anything here would have been an upper bound.

**Caveats.** Favourite and overround use first prints up to 2 tape minutes apart, as in 472, so a state may include a print slightly after the entry. Own-goal flip not relevant: FT and HT scores come from af_fixtures. Log read from the task output, not /root/pe-queue-logs.
