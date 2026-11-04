# Finder 2026-11-04 — item 48: racing residual model on BSP

**Data.** racing_bsp UK/IE, WIN and PLACE, 245,305 rows, 26,089 markets, Dec 2021–Oct 2026. Fit before 1 Jul 2025 (F1, 19,550 markets). Hold-out 1 Jul 2025–12 Oct 2026, 61,142 runners, 6,539 markets, split at 12 Mar 2026. Job: jobs/489_racing_residual.sh. No stall or going on the table, so neither was used. Distance reaches only 45.1% of PLACE rows (from the WIN race with the same course and time).

**Two signals.** A BSP order goes in before the BSP is known, so the item as written looks ahead.
- CLEAN (can pass): morning features only. GBM of outcome − 1/BSP; margin = predicted residual × morning WAP.
- AS_ITEM (cannot pass, reading only): adds pre-play WAP and BSP; margin = model p × BSP − 1.

**Fits.** F1 all history; F2 the item's window, Jan 2024–Jun 2025, ALL bands only; F3 F1's window with far simpler trees. F3 was added after seeing the first run's hold-out, so a pass on F3 alone would have been suspect. None occurred.

**Controls, hold-out, no model, per £10** (one tick / exact BSP)

| Line | n | Mean | Exact BSP | t | h1 | h2 |
|---|---|---|---|---|---|---|
| Win back | 32,168 | −0.837 | −0.495 | −3.03 | −0.937 | −0.716 |
| Win lay | 32,168 | −0.038 | −0.006 | −1.65 | −0.047 | −0.028 |
| Place back | 28,974 | −0.306 | −0.108 | −1.15 | −0.757 | +0.062 |
| Place lay | 28,974 | −0.123 | −0.059 | −2.66 | −0.139 | −0.109 |

**Top 15 CLEAN lines by t, n >= 300, hold-out. Survivors: none.** m = margin threshold; tc = t clustered by market; ex-top = mean without the largest win.

| Fit | Line | m | Sel | Band | n | Mean | t | tc | h1 | h2 | Exact BSP | ex-top |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| F3 | Lay place | .05 | one per race | all | 689 | +0.310 | 1.77 | 1.77 | +0.191 | +0.378 | +0.345 | +0.268 |
| F3 | Back win | .05 | all | 12-30 | 1,769 | +2.361 | 1.70 | 1.77 | +1.932 | +2.897 | +2.978 | +1.841 |
| F1 | Lay win | .20 | one per race | all | 1,513 | +0.117 | 1.36 | 1.36 | +0.147 | +0.087 | +0.136 | +0.079 |
| F3 | Lay win | .05 | all | 3-6 | 362 | +0.379 | 1.35 | 1.42 | +0.649 | +0.122 | +0.433 | +0.352 |
| F3 | Back win | .10 | all | 12-30 | 613 | +3.144 | 1.34 | 1.40 | +2.542 | +3.706 | +3.862 | +2.247 |
| F1 | Back win | .05 | one per race | 3-6 | 451 | +1.137 | 1.26 | 1.26 | +1.497 | +0.749 | +1.351 | +0.944 |
| F1 | Lay win | .20 | one per race | 30+ | 1,076 | +0.032 | 1.20 | 1.20 | +0.036 | +0.028 | +0.038 | +0.030 |
| F2 | Lay place | .10 | one per race | all | 2,046 | +0.178 | 1.16 | 1.16 | −0.080 | +0.338 | +0.234 | +0.138 |
| F3 | Lay place | .05 | all | all | 1,111 | +0.139 | 1.10 | 1.11 | +0.087 | +0.171 | +0.169 | +0.113 |
| F3 | Back place | .05 | all | all | 1,539 | +3.463 | 1.05 | 1.07 | −1.140 | +7.020 | +3.841 | +0.344 |
| F1 | Lay win | .05 | all | 12-30 | 3,301 | +0.040 | 1.04 | 1.11 | +0.039 | +0.040 | +0.060 | +0.039 |
| F3 | Back place | .10 | all | all | 326 | +15.521 | 1.03 | 1.04 | −1.767 | +37.923 | +16.211 | +0.798 |
| F1 | Lay win | .05 | one per race | 12-30 | 496 | +0.089 | 1.00 | 1.00 | −0.016 | +0.236 | +0.108 | +0.085 |
| F3 | Back place | .05 | one per race | all | 697 | +6.304 | 0.90 | 0.90 | −1.032 | +14.276 | +6.677 | −0.585 |
| F3 | Lay place | .05 | all | 12-30 | 327 | +0.112 | 0.90 | 0.92 | +0.322 | +0.005 | +0.132 | +0.081 |

**Calibration.** With BSP and pre-play data, model p is no closer to results than BSP is (top win decile: model 0.392, BSP 0.385, actual 0.381; top place decile: 0.710, 0.704, 0.706).

**Overfitting.** F1 CLEAN lines made +£3.95 to +£7.01 in-sample and −£0.06 to +£0.45 on the hold-out (back win). F3 removes most of that gap (back win +0.78, −0.72, −1.40 in-sample), and still nothing reaches the bar.

**Verdict: nothing passes.** 0 of 515 hold-out lines; 0 AS_ITEM numeric passes either. Best t is 1.77 against a required 3.5, and Bonferroni for this many lines is about 3.90. The place back lines are one £4,800 win on a very long price: +£15.52 falls to +£0.80 without it. BSP orders have no spread, so the exact-BSP column is the fairer cost; t was not computed at that cost, but it adds only £0.01–£0.06 on the lay lines at the top of the table, far short of what t 3.5 needs. Laying win at exact BSP is about break-even after commission (−£0.006, n 32,168), which fits a market with no residual to take.

**Defects found and fixed in this job (first run not used):** win_lose = 2 marks a dead heat (20 rows, 10 races, Jan 2022–Feb 2023), which the first run treated as losers; 17 rows in 3 races labelled win are place markets named "2 TBP" (14 rows in the hold-out). Jobs reading racing_bsp with win_lose = 1, such as 463, may carry the first defect; rows are few and all before 2023-03.

**Caveats.** Margin bands were reported whole, not chosen. Assumes the morning WAP closes before the earliest race (11:35), which the table does not state. PLACE dead heats are paid as full winners, which slightly flatters place backs and hurts place lays. The relabel ran after de-duplication, so at most 17 rows could repeat a runner. The runner also started job 489 by itself, on the first version: if job_results holds that run, this report supersedes it. Log not in /root/pe-queue-logs: this session could not redirect there, so it was read from the task output.
