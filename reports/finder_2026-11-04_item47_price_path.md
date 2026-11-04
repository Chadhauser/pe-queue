# Finder 2026-11-04, item 47: price-path signatures

**Data used:** bf_hist_price, MO and OU25 only, 1,100 games from 2024 and 1,096 priced from 2025 (about 18% of 12,255, a fixed hash order, cut to fit the 90 minutes). 48,338 entries in 2024, 48,822 in 2025. Share settled at the result, not dropped: +5 1.6%, +10 3.4%, +15 7.8%.

**Job:** jobs/488. The output is in the harness task file, as this run could not write to /root/pe-queue-logs. No fix was needed.

**Method:** entries at tape minutes 15, 20 … 80 on a real print at that minute, ltp 1.10–15. Features come only from prints in the previous 10 minutes, with at least 5 prints. Exit at the first print at or after +5/10/15, else the FT result. One tick adverse each way, 2% on profit, lay liability £10. 2024 chose the lines and only 2025 scored them, so the halves are the two sides of the 2025 date median.

**Not covered:** the tape has no volume, so that feature is missing. "Time since last goal" is left out, as the item also says no game-state inputs. liq_sample was not used. Ranked by 2025 t, not by P&L alone.

## Controls, every entry in 2025

| line | n | per £10 | t | h1 | h2 |
|---|--:|--:|--:|--:|--:|
| Back +5 | 48,822 | −0.279 | −15.77 | −0.298 | −0.259 |
| Lay +5 | 48,822 | −0.209 | −15.63 | −0.209 | −0.210 |
| Back +10 | 48,822 | −0.258 | −9.65 | −0.299 | −0.216 |
| Lay +10 | 48,822 | −0.196 | −9.80 | −0.205 | −0.187 |
| Back +15 | 48,822 | −0.228 | −6.59 | −0.293 | −0.163 |
| Lay +15 | 48,822 | −0.184 | −7.19 | −0.195 | −0.173 |

## Hold-out 2025, top 15 by t of 66 lines chosen on 2024, none passes

Cells are terciles 0–2 of drift over 10 and over 3 minutes and distance from the first print, and rng 0–1 for below or above the median range.

| line | n | games | per £10 | t | h1 | h2 | 2024 per £10 |
|---|--:|--:|--:|--:|--:|--:|--:|
| Lay +10 U2.5 d10=0 d3=1 rng=1 dist=1 | 173 | 145 | +0.502 | 1.35 | +0.098 | +1.081 | +0.384 |
| Lay +15 U2.5 d10=0 d3=1 rng=1 dist=0 | 196 | 164 | +0.530 | 0.80 | +0.527 | +0.535 | +0.685 |
| Back +5 U2.5 d10=0 d3=0 rng=0 dist=1 | 324 | 250 | +0.079 | 0.78 | +0.223 | −0.079 | +0.001 |
| Lay +10 Home d10=2 d3=2 rng=0 dist=1 | 128 | 121 | +0.159 | 0.67 | +0.329 | −0.052 | +0.117 |
| Lay +15 O2.5 d10=0 d3=1 rng=1 dist=1 | 129 | 121 | +0.263 | 0.54 | −0.072 | +0.615 | +0.455 |
| Lay +5 O2.5 d10=2 d3=2 rng=0 dist=2 | 159 | 143 | +0.052 | 0.45 | −0.049 | +0.142 | +0.025 |
| Lay +15 Draw d10=0 d3=1 rng=1 dist=0 | 236 | 206 | +0.133 | 0.42 | +0.122 | +0.147 | +0.574 |
| Lay +10 Draw d10=0 d3=1 rng=0 dist=0 | 465 | 333 | +0.038 | 0.36 | +0.052 | +0.025 | +0.098 |
| Lay +10 Draw d10=0 d3=1 rng=1 dist=0 | 236 | 206 | +0.066 | 0.28 | +0.175 | −0.074 | +0.188 |
| Lay +15 U2.5 d10=0 d3=1 rng=1 dist=1 | 173 | 145 | +0.089 | 0.21 | −0.169 | +0.461 | +0.368 |
| Back +10 U2.5 d10=1 d3=1 rng=0 dist=0 | 255 | 178 | +0.012 | 0.11 | +0.089 | −0.065 | +0.063 |
| Back +15 Away d10=0 d3=1 rng=0 dist=0 | 126 | 98 | +0.027 | 0.04 | −0.125 | +0.205 | +0.405 |
| Lay +10 Home d10=2 d3=2 rng=0 dist=2 | 229 | 175 | −0.004 | −0.02 | +0.039 | −0.049 | +0.100 |
| Lay +5 Draw d10=0 d3=1 rng=1 dist=0 | 236 | 206 | −0.022 | −0.14 | +0.098 | −0.176 | +0.108 |
| Back +15 O2.5 d10=2 d3=2 rng=0 dist=0 | 185 | 151 | −0.038 | −0.14 | −0.001 | −0.072 | +0.107 |

Lines positive in 2025: 12 of 66. The chosen state lines averaged +0.178 in 2024 and, with the GBM lines included, −0.188 in 2025, about the level of the controls, so the 2024 edge did not carry over.

**The GBM predicts direction but not profit.** Share of 2025 entries where the next print is shorter, base about 45%: +5 top decile 84.6%, bottom 13.0%; +10 77.0% and 17.0%; +15 72.9% and 18.6%. Yet no GBM line reaches the top 25 of 66, so each has t below −0.77; this job did not print their exact P&L. A leak looks unlikely, as the entry print and everything later are outside the features and the rates hold on 2025, but I did not break the result down, so what drives it is unproven. Lead → item 54.

## Verdict

Nothing passes: 0 of 66 lines on 2025, best t 1.35 (n 173). Prints are LTP, so these are upper bounds. Entries repeat within a game and the +10 and +15 windows overlap, so t is if anything inflated, and it still falls short. The sample is 18% of the games, so a small edge in one narrow state cannot be ruled out, but the fall from +0.178 to −0.188 gives no reason to expect one.
