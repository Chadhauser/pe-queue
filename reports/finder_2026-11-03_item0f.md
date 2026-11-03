# Finder 2026-11-03 — item 0f: two-season grid on AH / DNB / FH (jobs/467, census only)

**Premise checked, and it is false for AH and DNB.** Full census of bf_hist_price (jobs/467, first run, exact GROUP BY):

| mkt | sels | events | rows | minutes |
|---|---|---|---|---|
| MO | 3 | 37,121 | 6,845,124 | 0–96 |
| OU15 / OU25 / OU35 | 2 | 36,552 / 36,932 / 36,984 | 3.66M / 3.13M / 4.00M | 0–100 |
| BTTS | 2 | 33,229 | 1,268,620 | 0–100 |
| FH05 / FH15 | 2 (OVER/UNDER) | 35,073 / 36,533 | 1.89M / 2.01M | 0–100 |

There is **no AH and no DNB** in bf_hist_price. This agrees with item 8 (jobs/457). The only two-season-capable tables are bf_hist_price
and bf_hist_other. FH05/FH15 have already been run through the honest engine as item 14 (jobs/462: 12,185 games, 640 cells, nothing
passes, best FH15 0-0 25' LAY +£0.12 t 2.39), so they are not repeated here.

**bf_hist_other (new to the Finder, 56,357,164 rows):** sport, market_type, market_id, event, sel, ts, ltp, inplay. From the loaders
(jobs/064, jobs/129): cricket MO Jan–Mar 2026, GB/IE horse racing WIN May 2026, soccer Jul–Sep 2026 only. So even if it holds soccer
AH/DNB, it is ~3 months, not two seasons. The per-sport × market-type census timed out twice tonight (exact GROUP BY > 10 min;
2% TABLESAMPLE killed at 15 min with the bf_hist_price census in the same job). It is queued as its own item.

**Verdict: BLOCKED for AH/DNB** (missing data: two-season AH/DNB prints would need the Betfair historical BASIC files for
ASIAN_HANDICAP / DRAW_NO_BET market types, the same source as bf_hist_price; not downloaded, per the rules). FH part already
DONE as item 14: nothing passes.
