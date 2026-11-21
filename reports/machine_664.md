# 664 — 2026-11-19 07:08 UTC
```
machine compiles
team loop stopped: 0 left
/root/pe-sports/team/patch_664.py:35: DeprecationWarning: datetime.datetime.utcnow() is deprecated and scheduled for removal in a future version. Use timezone-aware objects to represent datetimes in UTC: datetime.datetime.now(datetime.UTC).
  tomorrow = (datetime.datetime.utcnow() + datetime.timedelta(days=1)).strftime('%Y-%m-%dT01:30:00')
money patched
settled_lines patched
M1 registered, first loop run 2026-11-20T01:30:00
team loop compiles
== first machine run
exit 0
RESULT lines: 35
/root/pe-sports/team/machine_nightly.py:141: DeprecationWarning: datetime.datetime.utcnow() is deprecated and scheduled for removal in a future version. Use timezone-aware objects to represent datetimes in UTC: datetime.datetime.now(datetime.UTC).
  if ok and rule not in FILT: FILT[rule] = dict(attr=a, value=(v.item() if hasattr(v, 'item') else v), adopted=dt.datetime.utcnow().isoformat()[:16])
# The machine — nightly run 2026-11-19 07:08 UTC

## 1. Results

Markets to settle tonight 1207: settled 941, not closed yet 0. Markets with a result in total: 941.

{
 "coherence paper": {
  "attr": "side",
  "value": "BACK",
  "adopted": "2026-11-19T07:08"
 }
}
[('coherence paper without side=BACK (forward from 2026-11-19)', 0)]
team loop running: 1
== wait for the running loop to rewrite the scoreboard (max 10 min)
2026-11-19 06:51:52 DATA BROKEN: ['goal signal alerts', 'API-Football results (finished fixtures, 48h)', 'coach tape']
2026-11-19 07:02:16 DATA BROKEN: ['goal signal alerts', 'API-Football results (finished fixtures, 48h)', 'coach tape']
2026-11-19 07:08:46 DATA BROKEN: ['goal signal alerts', 'API-Football results (finished fixtures, 48h)', 'coach tape']
## PROOF GATE — 100 settled paper bets, profit after commission overall and in each half, in line with the backtest; then Peter says yes
| rule | settled / 100 | £ after commission | £ per £100 | first half £ | second half £ | gate |
|---|---|---|---|---|---|---|
| bot TAKER — all passed cells | 82 / 100 | -2.85 | -1.74 | -3.02 | +0.18 | 18 more |
|   taker cell BOTH_TEAMS_TO_SCORE BACK | 4 / 100 | -8.00 | -100.00 | -4.00 | -4.00 | 96 more |
|   taker cell BOTH_TEAMS_TO_SCORE LAY | 6 / 100 | -0.20 | -1.67 | -0.10 | -0.10 | 94 more |
|   taker cell CORRECT_SCORE BACK | 6 / 100 | +4.15 | +34.60 | +10.15 | -6.00 | 94 more |
|   taker cell DRAW_NO_BET BACK | 1 / 100 | -2.00 | -100.00 | +0.00 | -2.00 | 99 more |
|   taker cell FIRST_GOAL_SCORER LAY | 3 / 100 | -7.68 | -128.00 | +1.96 | -9.64 | 97 more |
|   taker cell FIRST_HALF_GOALS_15 BACK | 4 / 100 | -8.00 | -100.00 | -4.00 | -4.00 | 96 more |
|   taker cell FIRST_HALF_GOALS_15 LAY | 3 / 100 | -1.88 | -31.33 | +1.96 | -3.84 | 97 more |
|   taker cell FIRST_HALF_GOALS_25 BACK | 2 / 100 | -4.00 | -100.00 | -2.00 | -2.00 | 98 more |
|   taker cell HALF_TIME LAY | 1 / 100 | +1.96 | +98.00 | +0.00 | +1.96 | 99 more |
|   taker cell HALF_TIME_FULL_TIME BACK | 2 / 100 | +2.02 | +50.45 | -2.00 | +4.02 | 98 more |
|   taker cell MATCH_ODDS BACK | 2 / 100 | -4.00 | -100.00 | -2.00 | -2.00 | 98 more |
|   taker cell MATCH_ODDS LAY | 3 / 100 | -1.60 | -26.67 | +1.96 | -3.56 | 97 more |
|   taker cell OVER_UNDER_25 BACK | 8 / 100 | +4.70 | +29.39 | +3.86 | +0.84 | 92 more |
|   taker cell OVER_UNDER_25 LAY | 7 / 100 | +7.26 | +51.86 | +5.88 | +1.38 | 93 more |
|   taker cell OVER_UNDER_45 LAY | 12 / 100 | +2.08 | +8.67 | -1.16 | +3.24 | 88 more |
|   taker cell WIN LAY | 18 / 100 | +12.34 | +34.28 | +10.00 | +2.34 | 82 more |
| bot v2.2 TAKER (blocklist + filters, from 17 Nov) | 44 / 100 | -18.25 | -20.74 | -14.56 | -3.69 | 56 more |
| small bites forward paper (all cells) | 1763 / 100 | -29.27 | n/a | +98.88 | -128.15 | FAIL (a half is negative) |
|   small bites DRIFT_FADE k3 H10 | 126 / 100 | +12.86 | n/a | +7.90 | +4.96 | PASS |
|   small bites DRIFT_FADE k5 H10 | 625 / 100 | -36.85 | n/a | +100.83 | -137.68 | FAIL (a half is negative) |
|   small bites STEAM_FOLLOW k2 H10 | 304 / 100 | -4.33 | n/a | +2.14 | -6.47 | FAIL (a half is negative) |
|   small bites STEAM_FOLLOW k2 H5 | 43 / 100 | -1.69 | n/a | -1.63 | -0.06 | 57 more |
|   small bites STEAM_FOLLOW k3 H10 | 301 / 100 | -2.53 | n/a | +2.17 | -4.71 | FAIL (a half is negative) |
|   small bites STEAM_FOLLOW k3 H5 | 32 / 100 | +0.35 | n/a | -1.71 | +2.06 | 68 more |
|   small bites STEAM_FOLLOW k5 H10 | 332 / 100 | +2.92 | n/a | +5.82 | -2.90 | FAIL (a half is negative) |
| coherence forward paper, real order book (all cells) | 23 / 100 | -3.48 | n/a | -6.72 | +3.24 | 77 more |
| v3 R1 home LAY 2% vs Pinnacle fair | 0 / 100 | +0.00 | n/a | +0.00 | +0.00 | 100 more |
| v3 R2 home BACK 5% vs Pinnacle fair | 0 / 100 | +0.00 | n/a | +0.00 | +0.00 | 100 more |
| machine fix: coherence paper without side=BACK (forward from 2026-11-19) | 0 / 100 | +0.00 | n/a | +0.00 | +0.00 | 100 more |
| desk FADE (lay scorer +2m, out +10m) | 401 / 100 | -9.12 | -1.14 | -23.03 | +13.91 | FAIL (a half is negative) |
| desk HT11 (1-1 HT, back O2.5) | 6 / 100 | +2.04 | +17.00 | +0.99 | +1.05 | 94 more |
| desk CELL (in-play cells) | 0 / 100 | +0.00 | n/a | +0.00 | +0.00 | 100 more |
| H0 fade forward paper (m1_alerts) | 0 / 100 | +0.00 | n/a | +0.00 | +0.00 | no table |

## Data health (24h)
# SPORTS SCOREBOARD (Verifier-only) — 2026-11-19T07:08 UTC

Money: live £0.00 | paper £-53.91 | live edges 0
```
Terminated
