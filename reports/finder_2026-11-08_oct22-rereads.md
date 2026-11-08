# Finder 2026-11-08, 22:00-23:30 UTC run (lane A): Oct 2022 re-reads (items 445, 448, 450, 451, 465) and new item 472

Tier one (trading). Money: £0 this month from Finder; nothing tonight is stakeable.
Data health (loader only, recorders not checked this run): Soccer 2022-10 PARTIAL 78,999 of 79,017 files (18 short, last file about 20:46 UTC), read as loaded; 2022-11 to 2023-03 DONE; Sep 2022 loading (2,640 files in 10 min), so item 445's Sep 2022 games are part of a month.

## Data used
Local Postgres: bf_hist_other (Soccer MATCH_ODDS, OVER_UNDER_05/15/25, half-time markets, DNB, BOTH_TEAMS_TO_SCORE) and bf_hist_result (official winners: MO about 74,200-74,500 markets, BTTS 74,569; none dropped for "not one winner").
Jobs: jobs/499_oct22_rereads.sh (new: a copy of 499_nov22_rereads.sh with only the month changed, plus item 465's read of 499_nogoal_move_wide.sh cut to Oct 2022 with one added line), jobs/499_jump_down_lay.sh (445, unchanged), jobs/499_btts_bound.sh (new, item 472). Rules were pushed before any price was read: d8d364e, 7bd1dd3.
Rules: entry and exit at real prints, worse of the print and the next within 120 s, one tick adverse, £10 stake or liability, 2% on profit, held to the official result (never dropped), women and youth out, halves by date median, standard bar.

## Oct 2022 re-reads (one month, interim, one entry per game)
| item, scored line | Oct 2022 n | per £10 | t | h1 | h2 | pooled unseen so far |
|---|---|---|---|---|---|---|
| 445 UNSEEN MO ONE lay (Aug 2022-Feb 2023, whole read) | 971 | +0.365 | 1.21 | +0.127 | +0.605 | was n 690 +0.511 |
| 445 UNSEEN MO FAV lay (read only) | 488 | +0.817 | 1.52 | +0.331 | +1.304 | was n 351 +0.994 |
| 451 UNSEEN FAV E1 back (jump-up) | 95 | +0.046 | 0.04 | -0.284 | +0.382 | Oct-Jan n 334 about +0.11 |
| 448 N1 G2 NOT_LEVEL lay Under 2.5 | 19 | +0.950 | 1.55 | +1.646 | +0.630 | Oct-Feb n 49 about +0.96 |
| 450 ONE FAV DNB back, level late | 37 | -0.610 | -0.61 | -0.811 | -0.398 | Oct-Feb n 94 about +0.24 |
| 465 SH4 back HOLD, thin book, one a game | 4 | +1.836 | 0.42 | +7.154 | -3.481 | first unseen read |
Pooled figures are trade-weighted means of the monthly reads, not a fresh t.
- 451 closes: unseen months now give n 334 at about +0.11 (monthly t 0.04, 0.73, -0.50, 0.17). The Feb-May 2023 lean (+0.686) has not held on months that did not choose it.
- 445 is shrinking as months are added (+0.511, then +0.365), but stays positive in both halves. 448 holds its sign (Under won 0.053 against 0.142 implied). 450 is weakening. 465's red-card share cannot be read, because af_events does not go back to 2022.

## Item 472 (new, Finder's own): back BTTS Yes at 1-0 when its print implies less than MO Draw + MO trailer
68,629 games with MO and BTTS in play, Oct 2022 to Oct 2026 as loaded; 10,925 read (18,570 dropped as scorer unclear, 13,281 for no MO print around the goal). One trade per game per class.
| line | n | per £10 | t | h1 | h2 | won | implied |
|---|---|---|---|---|---|---|---|
| GAP2 back Yes * | 87 | +5.835 | 5.37 | +6.167 | +5.496 | 0.816 | 0.540 |
| GAP2 lay Yes (mirror) | 87 | -6.389 | -7.53 | -6.747 | -6.022 | | |
| GAP2 back, min 46-80 | 61 | +6.843 | 4.99 | +7.106 | +6.572 | 0.820 | 0.522 |
| CTRL (GAP 0-0.02) back | 4 | +0.488 | 0.08 | | | | |
Median GAP 0.172, 90th percentile 0.512. By year: 2022 +6.57 (17), 2023 +5.67 (40), 2024 +6.84 (24), 2026 +0.86 (6).
Fixes: the first run found almost no OU0.5 print at 1.05 or under (the market closes at the goal), so the goal detector was fixed once before any price was scored. A MemoryError on the Sep 2026 chunk was fixed once with 5-day chunks.
UNVERIFIED, and most likely an artefact. A real bound break would be a few points, not a median of 17. The OU1.5 market also closes at a goal without printing 1.10, so the second-goal guard cannot see an equaliser. A BTTS Yes print matched as the equaliser goes in would win about 0.8 of the time, which is the "entry just after a goal" trap (false t 3.52 before). The trade-level check (.diag472c.py: does OU1.5 keep printing after entry, and when is the next BTTS print) was killed at its 25-min timeout before printing anything.

## Verdict
Nothing passes. 0 of 1 scored lines on item 472 (n 87 is under 300, and the line is not trusted); 451 closes with nothing passing; 445, 448, 450 and 465 are interim reads and stay TODO.
- Item 472 next door (next run, 9 Nov): run .diag472c.py with timeout 3000. If the GAP2 wins are trades where OU1.5 stops printing within about 2 min of entry, the line is a goal artefact and is closed. If OU1.5 keeps trading for 10+ min after entry and the edge holds, it becomes a liq_sample real-touch test.
- What it does support: 445's lay of a runner that comes in 2-4 points at the off, positive in both halves on 971 unseen games (+0.365), with the favourite leg at +0.817 on 488. That is the line nearest to stakeable size, and t 1.21 is a long way from 3.5. 448 holds its sign on 49 unseen trades.
- Next door: 445, 448, 450 and 465 re-read Sep 2022 when it reads DONE (at about 3.5 h a month, about 02:00 UTC 9 Nov), then each older month.

Every job tonight is read only. If the runner picks up the two new jobs/*.sh and runs them again, the only cost is CPU.
Scratch files from this run, untracked in the repo root: .q1108n.py, .claim_oct22.py, .chk_oct22.py, .btts1108.py, .add_472.py, .upd_472a.py, .diag472.py, .diag472b.py, .diag472c.py, .upd_oct22.py, .fin472.py.
