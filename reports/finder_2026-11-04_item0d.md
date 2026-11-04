# Finder 2026-11-04 — item 0d: team-sheet lag

**Verdict: nothing passes.** 0 of 42 trade lines. Every line loses, including the controls.

**Data:** af_lineups (890 fixtures, 13 Oct–3 Nov, already loaded, 0 API calls), af_events and af_fixtures (goals strictly before kick-off), stream_ticks football MO_PRE (31 Oct–4 Nov, 819 markets, the only pre-match touch on the box). 185 markets matched a fixture with a line-up; 135 games joined (22 leagues); 49 had no T-90 book on both sides, 1 had no favourite. Log: harness output only, this session could not write to /root/pe-queue-logs.

**Proxy:** publication time cannot be recovered, so T-60 stands in for it, as the item says. A T-60 entry assumes the sheet is read the moment it appears; T-45 and T-30 are the safer tests.

**Sample:** FAV_MISSING 60 games, just at the item's n >= 60 line. The groups that carry the real news are below it: FAV_SURPRISE 30, OPP_SURPRISE 23, FAV_TOP1 13. n >= 300 is out of reach while stream_ticks rolls at about 4 days.

## Does the price move after T-60? (favourite mid, %, positive = lengthens)
| Group v control | Window | n | Mean | Control | Diff | Welch t | >=3% expected way |
|---|---|---|---|---|---|---|---|
| FAV_MISSING v FAV_FULL | T-60 to KO | 60 | -0.29 | +0.50 | -0.80 | -0.82 | 30.0% v 21.4% |
| FAV_MISSING v FAV_FULL | T-45 to KO | 60 | +0.24 | +0.10 | +0.14 | +0.20 | 21.7% v 11.9% |
| FAV_SURPRISE v FAV_FULL | T-60 to KO | 30 | +0.24 | +0.50 | -0.26 | -0.21 | 30.0% v 21.4% |
| FAV_SURPRISE v FAV_FULL | T-45 to KO | 30 | +0.65 | +0.10 | +0.55 | +0.59 | 26.7% v 11.9% |
| FAV_TOP1 v FAV_FULL | T-45 to KO | 13 | +1.23 | +0.10 | +1.13 | +1.10 | 30.8% v 11.9% |
| OPP_MISSING v OPP_FULL | T-60 to KO | 49 | -1.38 | +0.10 | -1.48 | -1.68 | 32.7% v 15.9% |
| OPP_SURPRISE v OPP_FULL | T-60 to KO | 23 | -1.90 | +0.10 | -2.00 | -1.87 | 34.8% v 15.9% |
| OPP_SURPRISE v OPP_FULL | T-45 to KO | 23 | -0.63 | +0.38 | -1.01 | -1.25 | 13.0% v 11.4% |

No group's mean reaches the item's 3% move, and no difference is significant across 24 comparisons. When the favourite's own scorer is out, it does not drift more than a full-strength favourite after T-60.

## Trades per £10, top 15 by t (one per game; no line is a survivor)
| Group | Trade | Entry | n | Per £10 | t | n1 | h1 | n2 | h2 |
|---|---|---|---|---|---|---|---|---|---|
| OPP_SURPRISE | back fav | T-60 | 23 | -0.058 | -0.72 | 6 | -0.003 | 17 | -0.078 |
| OPPout_FAVfull | back fav | T-60 | 13 | -0.160 | -1.58 | 2 | -0.299 | 11 | -0.135 |
| FAV_TOP1 | lay fav | T-45 | 13 | -0.188 | -1.76 | 3 | -0.505 | 10 | -0.093 |
| OPPout_FAVfull | back fav | T-45 | 13 | -0.144 | -1.84 | 2 | -0.055 | 11 | -0.161 |
| OPP_TOP1 | back fav | T-60 | 21 | -0.138 | -1.87 | 4 | -0.171 | 17 | -0.130 |
| FAV_TOP1 | lay fav | T-30 | 13 | -0.190 | -1.88 | 3 | -0.498 | 10 | -0.097 |
| FAV_TOP1 | lay fav | T-60 | 13 | -0.232 | -1.89 | 3 | -0.505 | 10 | -0.150 |
| OPP_MISSING | back fav | T-60 | 49 | -0.120 | -1.95 | 10 | -0.097 | 39 | -0.126 |
| FAV_SURPRISE | lay fav | T-60 | 30 | -0.388 | -2.61 | 7 | -0.765 | 23 | -0.273 |
| BOTH_FULL | lay fav | T-60 | 17 | -0.519 | -2.65 | 5 | -0.931 | 12 | -0.348 |
| FAV_SURPRISE | lay fav | T-45 | 30 | -0.350 | -2.79 | 7 | -0.699 | 23 | -0.243 |
| BOTH_FULL | lay fav | T-45 | 17 | -0.527 | -2.82 | 5 | -1.000 | 12 | -0.330 |
| OPPout_FAVfull | back fav | T-30 | 13 | -0.205 | -2.99 | 2 | -0.194 | 11 | -0.206 |
| OPP_SURPRISE | back fav | T-30 | 23 | -0.173 | -3.09 | 6 | -0.254 | 17 | -0.144 |
| FAVout_OPPfull | lay fav | T-60 | 20 | -0.302 | -3.17 | 6 | -0.433 | 14 | -0.246 |

For scale, all 135 games: back fav T-60 -0.267, lay fav T-60 -0.415. That is roughly the cost of crossing the spread. Halves are too uneven in the small groups to mean much.

**Verdict:** nothing passes. Best is back the favourite at T-60 when the opponent's scorer who started last game is out: -£0.058 per £10, n 23. It is the only hint of a lag, it fades by T-45 (t -1.25), and it needs the sheet read instantly. Forward recorder queued as item 40.

## Defects found
- **First run void.** af_lineups spells one man several ways across fixtures, so name comparison marked Haaland absent from a game he scored in: 35 absent-but-scored. jobs/486 is the test; on player_id it reads 0, and absent labels fall from 604 to 238. **Any later job comparing line-up names must use player_id.**
- **Exclusions.** 363 of 1,728 team-games with a usable XI have a key scorer who cannot be resolved; they count as neither missing nor full. 310 line-up rows have no player_id.
- **Halves.** The first run split at the median day (113 v 22 games); now the median game (37 v 98), which is still uneven.
- **Shared database.** Job 485's first run died on Postgres `DiskFull` (shared memory) while running beside 484. Other queries at that moment may also have failed; not checked.
