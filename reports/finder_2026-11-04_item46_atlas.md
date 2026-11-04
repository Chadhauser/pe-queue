# Finder 2026-11-04 — item 46 atlas: football in-play calibration atlas

**Status: INCOMPLETE. NO VERDICT. Do not read this as "nothing passes".**

Job: jobs/488_calibration_atlas.sh. Tables: bf_hist_price (MO, OU15, OU25, OU35, BTTS, FH05, FH15), af_events, af_fixtures, af_price_map.

## What happened
- Raw prints for 178 of 246 chunks (up to 8,900 of 12,255 games, random order, seed 488) are cached in /root/pe-queue-logs/488_cache.
- The first full run was killed at 3,000 s (exit 124) with an empty log, because grep was buffering its output. A cache-only rerun was killed at 660 s, stuck after the fetch phase.
- Rows for 592 games build in 9 s, so row building is not the stall. The likely cause is the single large af_events query, not proven. It is now split into chunks of 500 with progress lines.
- The only full pass through the scoring code is the 592-game smoke test: 276 games of 2024, 316 of 2025.

## Smoke test, for checking the code only (not a result)
0 of 10 lines survive, none near n 300, because almost no leaf reached 100 games in 2024. The top 40 rule step has therefore not really been exercised.
GBM correlation with the residual: 0.664 in sample, 0.012 on hold-out.

| Selection (per row, rows share games) | residual 2024 | residual 2025 | lay £/£10 2025 |
|---|---|---|---|
| FH05 OVER | −0.058 | −0.037 | +0.64 |
| FH15 OVER | −0.027 | −0.038 | +0.38 |
| OU15 OVER | −0.021 | −0.015 | +0.08 |
| OU25 OVER | −0.011 | −0.019 | +0.12 |

The 90-94' band loses on both sides (back −£4.96, lay −£3.54 per row, 2025), which looks like stale prints. Not investigated.

## Honesty rules as built
One entry per game; 2024 fits, 2025 scores; 2025 halves by median date; a goal counts as known 5 tape minutes after its af minute (probe on 100 games: none later than +5); no row dropped for a later goal; settled markets go to the result. The af seasons overlap in time (Jan to Jun 2025), so the split is by season label, not strictly by date. LTP only, so any pass is an upper bound.

## Verdict
None. Item 46 atlas stays open: see the queue line for what is left.
