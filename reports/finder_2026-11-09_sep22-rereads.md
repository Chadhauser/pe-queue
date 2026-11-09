# Finder 2026-11-09, 02:20-02:55 UTC run (lane A): Sep 2022 re-reads (items 445, 448, 450, 451, 465) and new item 479

Tier one (trading). Money: £0 this month from Finder; nothing tonight is stakeable.
Data health (loader only, recorders not checked this run): Soccer 2022-09 DONE (66,193 of 66,193 files, about 00:56 UTC 9 Nov); 2022-10 PARTIAL 78,999 of 79,017 (18 short, read as loaded); 2022-11 to 2023-03 DONE; Aug 2022 still loading (2,688 files in the last 10 min), so its games are part of a month.

## Data used
Local Postgres: bf_hist_other (Soccer MATCH_ODDS, OVER_UNDER_25, half-time markets, DNB) and bf_hist_result (official winners: MO 77,987-78,036 markets, OU25 78,020; none dropped for "not one winner"). 91,976 MO games read for item 479 (10,135 women or youth out, 13,671 with no official result, 13,763 with roles unclear).
Jobs: jobs/499_sep22_rereads.sh (new: a copy of 499_oct22_rereads.sh with only the month changed), jobs/499_jump_down_lay.sh (445, unchanged), jobs/499_dn24_green_exit.sh (new, item 479). Item 479's rule was pushed before any price was read (commit "new item 479, rule fixed before any price").
Rules: entry and exit at real prints, worse of the print and the next within 120 s, one tick adverse, £10 stake or liability, 2% on profit, held to the official result where there is no exit (never dropped), women and youth out, halves by date median, standard bar.

## Sep 2022 re-reads (one month, interim, one entry per game)
| item, scored line | n | per £10 | t | h1 | h2 | pooled unseen so far |
|---|---|---|---|---|---|---|
| 445 UNSEEN MO ONE lay (Aug 2022-Feb 2023, whole read) | 1,181 | +0.222 | 0.81 | +0.045 | +0.398 | was n 971 +0.365 |
| 445 UNSEEN MO FAV lay (read only) | 594 | +0.398 | 0.81 | -0.355 | +1.150 | was n 488 +0.817 |
| 445 UNSEEN OU25 OVER lay | 430 | -0.302 | -0.57 | -1.307 | +0.704 | was n 348 +0.194 |
| 451 UNSEEN FAV E1 back (closed item, for the record) | 72 | +0.563 | 0.47 | +2.623 | -1.497 | Sep-Jan n 406 about +0.19 |
| 448 N1 G2 NOT_LEVEL lay Under 2.5 | 25 | +0.244 | 0.31 | +0.596 | -0.034 | Sep-Feb n 74 about +0.72 |
| 450 ONE FAV DNB back, level late | 37 | +0.314 | 0.30 | +0.144 | +0.495 | Sep-Feb n 131 about +0.26 |
| 465 SH4 back HOLD, thin book, one a game | 4 | +4.334 | 0.47 | -0.786 | +9.455 | Sep-Oct n 8 about +3.09 |
Pooled figures are trade-weighted means of the monthly reads, not a fresh t. 445's read is the whole unseen window, so its n is a fresh figure.
- 445 shrinks for the third read running (+0.511, +0.365, +0.222), and the favourite leg's first half has turned negative. 448 holds its sign (Under won 0.120 against 0.150 implied) but is weaker. 450 holds its sign. 465 is too small to read.

## Item 479 (new, Finder's own): lay the MO runner that shortened 2-4 points at the off, back out 10-15 min later
| line | n | per £10 | t | h1 | h2 | exited |
|---|---|---|---|---|---|---|
| MO ONE green (scored) | 3,127 | -0.167 | -2.30 | -0.122 | -0.212 | 0.816 |
| MO FAV green (scored) | 1,469 | -0.242 | -1.87 | -0.148 | -0.336 | 0.859 |
| MO OUT green | 1,016 | -0.173 | -1.86 | +0.003 | -0.349 | 0.820 |
| MO DRAW green | 642 | +0.015 | 0.13 | -0.205 | +0.235 | 0.713 |
| MO ONE green, exited trades only | 2,553 | -0.236 | -5.52 | -0.192 | -0.280 | 1.000 |
| before Mar 2023: MO ONE green | 1,181 | -0.089 | -0.69 | -0.004 | -0.173 | 0.803 |
| MO ONE held to the result (445's figure, all months) | 3,127 | +0.131 | 0.82 | +0.391 | -0.128 | |
| CONTROL FLAT, one a game | 30,250 | -0.265 | -18.23 | -0.240 | -0.290 | 0.915 |
| CONTROL FLAT DRAW | 19,447 | -0.156 | -11.80 | -0.143 | -0.168 | 0.906 |
By year, MO ONE green: 2022 -0.068 (881), 2023 -0.166 (1,410), 2024 -0.368 (693), 2026 +0.193 (143).
Cross-check: 479's before-Mar-2023 set is 1,181 games, the same count as 445's unseen MO ONE, from separate code paths. The hand-worked asserts for the green exit, the worse-of-two exit fill and the hold-to-result fallback all pass.

## Verdict
Nothing passes. Item 479: 0 of 2 scored lines (ONE -0.167 t -2.30, FAV -0.242). On exited trades the shortened runner does only about 0.03 per £10 better than a quiet one (-0.236 v the FLAT control's -0.265, which is 91.5% exited). That is far less than two crossings cost. 445, 448, 450 and 465 are interim and stay TODO.
- What it does support: 445's edge, such as it is, comes from the result and not from a fast drift back. It is still positive on 1,181 unseen games (+0.222), but it is shrinking and t is 0.81. The Draw that comes in at the off is the one leg that drifts back more than the control (+0.015 v -0.156). That is in-sample tonight and never scored.
- Next door: item 480 (new, re-check 22 Nov 2026). Lay that Draw at the real touch in liq_sample and exit with a resting back, which saves one crossing. 445, 448, 450 and 465 are re-read when Aug 2022 reads DONE, then each older month.
- 445 heads for closure. If the Aug 2022 read takes MO ONE under +0.15, or turns either half negative, it closes with nothing passing. Its door is then 480.

No other TODO item could run tonight. Every other item waits on a re-check date (12, 14 and 22 Nov), a loader month or a recorder.
Every job tonight is read only. If the runner picks up the two new jobs/*.sh and runs them again, the only cost is CPU.
Scratch files from this run, untracked in the repo root: .q1109.py, .q1109b.py, .q1109c.py, .claim_sep22.py, .add_479.py, .upd_sep22.py.
