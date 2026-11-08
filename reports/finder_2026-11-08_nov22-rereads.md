# Finder 2026-11-08, 16:00-16:35 UTC run: Nov 2022 re-reads (items 445, 448, 450, 451) and new item 461

Tier one (trading). Money: £0 this month from Finder; nothing tonight is stakeable.
Data health (loader only, recorders not checked this run): Soccer 2022-11 DONE 53,502 of 53,502 files (DB clock 16:48, about 15:48 UTC), 2022-12 to 2023-03 DONE; 2,688 files loaded in the last 10 min; Oct 2022 has no month row yet.

## Data used
Local Postgres: bf_hist_other (Soccer MATCH_ODDS, OVER_UNDER_25, HALF_TIME markets, DNB), bf_hist_result (official winners: MO 68,723 to 69,016 markets, OU25 68,764, none dropped for "not one winner").
Jobs: jobs/499_jump_down_lay.sh (445, unchanged), jobs/499_nov22_rereads.sh (new: a copy of 499_dec22_rereads.sh with only the month changed, runs 451, 448 and 450 on Nov 2022), jobs/499_mo_underround_ko.sh (new, item 461).
Rules: entry and exit at real prints, worse of the print and the next within 120 s, one tick adverse, GBP 10 stake or liability, 2% on profit, held to the official result (never dropped), women and youth out, halves by date median, standard bar.

## Item 445: lay a runner whose first in-play print is 2-4 points shorter than its last pre-off print (UNSEEN = before Mar 2023)
| line | n | per £10 | t | h1 | h2 |
|---|---|---|---|---|---|
| UNSEEN MO ONE lay * | 690 | +0.511 | 1.43 | +0.835 | +0.188 |
| UNSEEN OU25 OVER lay * | 212 | +0.656 | 0.86 | +0.285 | +1.028 |
| UNSEEN MO FAV lay | 351 | +0.994 | 1.58 | +1.351 | +0.635 |
| UNSEEN MO ONE D5 lay | 560 | +0.836 | 1.56 | +1.517 | +0.154 |
| AUDIT Mar 2023-Sep 2026 MO ONE lay | 1,946 | +0.076 | 0.39 | +0.372 | -0.220 |
| AUDIT 2024 MO ONE lay | 693 | -0.291 | -0.90 | -0.364 | -0.217 |
One trade per game (690 games). n clears 300 and both halves are positive, but t 1.43 is well under 3.5. The months after Feb 2023 hold the lay at +0.076, so the unseen lean has not shown up anywhere else yet.

## Items 451, 448, 450 on Nov 2022 (one month, interim, one entry per game)
| item, scored line | Nov 2022 n | per £10 | t | h1 | h2 | pooled unseen so far |
|---|---|---|---|---|---|---|
| 451 UNSEEN FAV E1 back (jump-up) | 70 | +0.904 | 0.73 | +2.401 | -0.593 | Nov-Jan n 239 about +0.14 |
| 448 N1 G2 NOT_LEVEL lay Under 2.5 | 13 | +0.796 | 0.88 | +1.658 | -0.584 | Nov-Feb n 30 about +0.97 |
| 450 ONE FAV DNB back, level late | 22 | +1.412 | 1.70 | +2.254 | +0.570 | Nov-Feb n 57 about +0.80 |
Pooled figures are trade-weighted means of the monthly reads, not a fresh t. All three stay TODO and need older months.

## Item 461 (new, Finder's own): back the stale leg of an MO book whose last pre-off prints add up to under 100%
20,756 games, Nov 2022 to Oct 2026 as loaded, one trade per game. The rule was pushed (commit 829b8b4) before any price was read.
| line | n | per £10 | t | h1 | h2 | won | implied |
|---|---|---|---|---|---|---|---|
| U3 (sum < 0.97) STALE back * | 195 | -0.360 | -0.28 | -1.490 | +0.782 | 0.308 | 0.327 |
| U1 (0.97-0.99) STALE back * | 2,062 | +0.029 | 0.05 | +0.451 | -0.394 | 0.319 | 0.325 |
| U1 STALE lay (mirror) | 2,062 | -0.129 | -0.77 | -0.181 | -0.077 | | |
| FAIR STALE back (control) | 18,195 | -0.406 | -3.34 | -0.357 | -0.456 | | |
| O3 (sum > 1.03) STALE back | 304 | +0.641 | 0.69 | +0.175 | +1.107 | | |
| U3+U1 back, 2026 only | 236 | -1.468 | -1.55 | | | | |
Caveat: a game counts only if the stale leg does not trade again before the off, and that is not known at t*. This is a small look-ahead in which games get picked. It cannot rescue a losing line, but item 462 must define the stale leg at a fixed time instead (e.g. KO-2 min).
Why it fails: the stale leg's next print came in-play in 98% of U3 entries. By then it had shortened in 76% of cases (median -4.5%, against -1.3% in FAIR books), so the gap closes at the off, before a taker can reach it.

## Verdict
Nothing passes. 0 of 2 scored lines on item 461; 445, 448, 450 and 451 are interim reads that stay TODO.
- What it does support: 445's MO lay is positive in both halves on 690 unseen games (+0.511), and the FAV leg reads +0.994 on 351. That is the one line here near the size we need, but at t 1.43 it is not stakeable.
- Next door for 445: it re-runs as Oct 2022 and older months load (loader about 270 files/min, about 3.5 h a month). Next check 12 Nov.
- Next door for 461 (queued as item 462, re-check 22 Nov): the same under-100% state read at the real touch on liq_sample. If the stale leg's best back is still at or above its stale print at t*, back at the touch. That shows whether the value is ever offered before the off, or whether only the last price is out of date.

The two new jobs are read only. If the runner picks them up as new jobs/*.sh and runs them a second time, the only cost is CPU, and no table is written.
Scratch files from this run, untracked in the repo root: .q1108e.py, .claim_445b.py, .make_nov22.py, .kw1108e.py, .claim_461.py, .upd_nov22.py, .upd_461.py.
