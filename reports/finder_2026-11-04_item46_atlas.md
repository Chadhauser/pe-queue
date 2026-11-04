# Finder 2026-11-04 — item 46 atlas: football in-play calibration atlas

**Status: PARTIAL. 2,953 of 12,255 games, random sample (seed 488), first 60 of the 178 cached chunks. Nothing passes on this sample; the full set is item 46b.**

Job: jobs/488_calibration_atlas.sh. Data: bf_hist_price (MO, OU15, OU25, OU35, BTTS, FH05, FH15), af_events, af_fixtures, af_price_map. Fit on 1,383 games of season 2024 (226,016 rows), scored on 1,570 games of season 2025. 33 games dropped on kick-off lag, 14 where event goals differ from FT. Known-answer checks pass.

## Hold-out 2025, one entry per game, per £10, top 15 of 88 lines by t (S = settle, G = next goal +8; no survivors)
| Rule | Side | Exit | n | per £10 | t | h1 | h2 | x3 | 2024 in sample |
|---|---|---|---|---|---|---|---|---|---|
| #4 OU15 UNDER R18 | B | S | 138 | +2.298 | 1.66 | +2.07 | +2.48 | +2.03 | +7.19 |
| #4 OU15 UNDER R18 | B | G | 138 | +1.870 | 1.60 | +2.09 | +1.69 | | +4.10 |
| #3 OU15 OVER R17 | L | S | 141 | +2.236 | 1.58 | +1.82 | +2.58 | +1.82 | +7.32 |
| #3 OU15 OVER R17 | L | G | 141 | +1.820 | 1.50 | +1.75 | +1.88 | | +4.08 |
| #15 OU35 OVER R37 | L | S | 309 | +0.384 | 1.04 | +0.33 | +0.44 | +0.27 | +1.03 |
| #29 MO AWAY G39 | L | S | 246 | +0.501 | 1.03 | +1.19 | −0.11 | +0.37 | +0.35 |
| #12 MO DRAW G31 | L | G | 94 | +0.313 | 0.98 | +0.54 | +0.06 | | +0.25 |
| #13 OU15 OVER R20 | L | S | 134 | +1.194 | 0.81 | +0.75 | +1.57 | +0.77 | +2.14 |
| #17 MO AWAY R10 | B | G | 205 | +0.321 | 0.68 | +1.12 | −0.36 | | +1.64 |
| #5 MO DRAW R5 | L | G | 75 | +0.275 | 0.66 | +0.77 | −0.19 | | +0.88 |
| #19 OU15 UNDER R20 | B | S | 134 | +0.874 | 0.63 | +0.69 | +1.04 | +0.62 | +2.04 |
| #16 OU25 OVER R46 | L | S | 448 | +0.288 | 0.57 | −0.03 | +0.59 | +0.12 | +0.42 |
| #7 OU25 UNDER R46 | B | S | 417 | +0.288 | 0.54 | −0.25 | +0.77 | +0.13 | +1.04 |
| #20 OU25 OVER G20 | L | G | 141 | +0.265 | 0.51 | +1.07 | −0.49 | | +0.14 |
| #14 OU35 UNDER R10 | B | S | 329 | +0.163 | 0.47 | +0.14 | +0.19 | +0.01 | +0.85 |

## What the map shows
- All 88 lines: hold-out mean −£0.30 against +£1.83 on the fit season; 29.5% positive; only 28 lines reach n 300.
- GBM: correlation with the residual 0.475 in sample, −0.013 on hold-out; the 2025 deciles show no order, so the model found nothing that lasted.
- Trees on the actual residual: leaves in 2024 v 2025, spearman 0.449, same sign 62.9% (35 leaves). Trees on the GBM's prediction: 0.052, 44.2% (43 leaves). Mean leaf error shrinks from 0.066 to 0.027. Some of the map may persist; the sample is thin, leaves share games, and the top leaves pick leagues on the fit season's own residual.
- By selection the 2024 errors mostly did not repeat: OU25 Over −0.030 then −0.003, BTTS Yes −0.031 then 0.000, MO Away −0.014 then +0.007. OU15 Over is the exception, −0.032 then −0.013.
- By 5-minute band and by score the residual is within about ±0.005 in both seasons where n is large. The 90-94' band loses both ways (back −£4.89, lay −£3.64 per row), which looks like stale prints; not investigated.
- The first-half Over lead from the 592-game smoke test did not hold: FH05 Over 2025 +0.0085, lay −£0.31. Not queued.

## Verdict
Nothing passes on this sample: 0 of 88 lines. This is not a verdict on the full set, as a rule must fire in about a fifth of 1,570 games to reach n 300. Best line: back OU15 Under R18, n 138, t 1.66, positive in both halves, with a largest win of £86 in the line, so it is well short of the bar → item 55. LTP only, so any pass would be an upper bound.

## Run notes
Two earlier runs were killed at their limits (3,000 s and 660 s) with no result; the 3,000 s run's log was empty because grep buffered it. Chunking the af_events query cleared the stall (this run took about 2 min), which points to that query as the cause, though it was not timed directly. Row memory was also compacted. The af seasons overlap in time (Jan to Jun 2025), so the split is by season label. The log went to the harness task output, not /root/pe-queue-logs, as the permission check blocked that redirect.
