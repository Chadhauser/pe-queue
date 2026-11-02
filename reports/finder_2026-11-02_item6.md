# Finder 2026-11-02 — queue item 6: RED CARDS AS A STATE

**Job:** jobs/455_red_cards.sh (P&L engine of 452, unit-asserted). **Data:** bf_hist_price (1-min LTP) + af_events via af_price_map;
12,255 mapped games (2024: 5,871, 2025: 6,384); 2,238 sendings-off in 1,981 games (af_events has only 'Red Card' — second yellows are
not split out). First sending-off per game only → one entry per game per trade; no within-line correlation.
**Rules:** decision at the first real print card+2..+4; fill = worse of that and the next real print within 2 min, one tick adverse;
exits +10 / +20 min (first real print at/after, any later minute) or settle; no exit print → settled at result; Over 2.5 settled as a
win if the 3rd goal lands before the exit (102 at +10, 207 at +20); not traded if already 3+ goals. £10 risk, 2% commission. h1 = 2024, h2 = 2025.
Excluded and counted: card after 85' (465), no print at card+2..+4 (111/146/119 by leg), back at 1.01 unfillable (348).

## Price paths (median LTP at decision / +10 / +20)
11-man side 1.80 → 1.72 → 1.63 (won 54.4%); 10-man side 9.5 → 12.0 → 13.5 (won 18.9%); Over 2.5 2.62 → 2.98 → 3.30 (won 41.9%).

## Headline (per £10)
| line | n | per £10 | t | h1 (2024) | h2 (2025) |
|---|---|---|---|---|---|
| back 11-man, settle | 1,285 | +2.15 | 1.17 | +3.72 | +0.75 |
| back 11-man, +20 | 1,285 | +2.03 | 1.12 | +3.95 | +0.30 |
| back 11-man, +10 | 1,285 | +1.96 | 1.10 | +4.07 | +0.07 |
| lay 10-man, settle | 1,366 | +0.51 | 1.58 | +0.77 | +0.29 |
| lay 10-man, +20 | 1,366 | +0.35 | 1.19 | +0.50 | +0.21 |
| lay 10-man, +10 | 1,366 | +0.17 | 0.63 | +0.39 | −0.03 |
| back Over 2.5, +10 | 1,105 | −0.45 | −1.39 | −0.43 | −0.46 |
| back Over 2.5, +20 | 1,105 | −0.78 | −2.51 | −1.02 | −0.56 |
| back Over 2.5, settle | 1,105 | −1.14 | −2.87 | −1.67 | −0.66 |
The back-11-man mean is driven by a few long shots (avg fill price 10.1; 10-man-behind/60+ cells avg 20): t ≈ 1.1, not tradable.

## Top lines by t (n ≥ 30; none passes)
| line | n | per £10 | t | h1 | h2 |
|---|---|---|---|---|---|
| back 11-man +10, Segunda División | 130 | +2.64 | 2.01 | +0.86 | +4.30 |
| lay 10-man +20, 30-60', 10-man behind | 181 | +0.11 | 1.90 | −0.02 | +0.21 |
| lay 10-man +20, Eredivisie | 65 | +1.73 | 1.89 | +1.39 | +2.04 |
| back 11-man settle, <30' | 241 | +1.25 | 1.85 | +0.07 | +2.14 |
| lay 10-man settle, 30-60', 10-man ahead | 158 | +1.77 | 1.76 | +2.10 | +1.49 |
| back 11-man settle, 10-man level | 574 | +1.23 | 1.58 | −0.06 | +2.35 |
Best t anywhere is 2.01 on n 130; at ~100 lines tested, t ≈ 2 is what chance alone produces.

## Verdict
**Nothing passes.** The red card is priced in by the first real print two minutes later. Laying the 10-man side is the most consistent
direction (+£0.51 settle, both seasons positive), but t 1.6 is far short of 3.5. Backing Over 2.5 after a red is negative in every split.
