# Finder 2026-11-08 (04:00-04:20 UTC): item 444, and the March/April 2023 re-reads of eight leads

Money: £0 this month; no line has passed the bar tonight. Tier one (trading).
Data health (local DB, jobs/499_loader_progress.sh, item 70): Soccer 2023-03 DONE about 04:05 UTC (56,192 files), 2023-04 DONE, 2023-02 loading at 262 files/min; 26 stale months unchanged (18 LISTFAIL Nov 2024 to Apr 2026, 8 PARTIAL a few files short); disk free 57 GB, local DB 63 GB.

## Item 444: item 414's jump-up back on Over/Under 2.5 (new market, can pass)
Data: bf_hist_other OVER_UNDER_25 Apr 2023 to Sep 2026, bf_hist_result official winners (58,304 markets), 1,365 games traded. Rule fixed in the queue before any OU price was read (commit f1858bd). Job jobs/499_jump_up_ou25.sh, 380 s.

| line | n | games | per £10 | t | h1 | h2 | won | implied |
|---|---|---|---|---|---|---|---|---|
| ONE E1 worse of print and next (scored) | 1,365 | 1,365 | -0.019 | -0.06 | +0.404 | -0.501 | 0.504 | 0.497 |
| ONE E2 next print only | 711 | 711 | -0.392 | -0.98 | -0.257 | -0.556 | 0.484 | 0.491 |
| ONE E3 three ticks | 1,365 | 1,365 | -0.179 | -0.56 | +0.221 | -0.636 | | |
| UNDER E1 | 486 | | +0.218 | 0.30 | +1.680 | -1.245 | 0.451 | 0.445 |
| OVER E1 | 879 | | -0.150 | -0.46 | -0.237 | -0.043 | 0.534 | 0.525 |
| price 2.5-50 E1 | 324 | | +0.728 | 0.68 | +2.347 | -1.569 | | |
| year 2023 / 2024 / 2026 E1 | 681 / 534 / 150 | | +0.556 / -0.316 / -1.573 | 1.02 / -0.73 / -2.02 | | | | |
| CONTROL UP 1-2 / DOWN 2-4 back | 3,478 / 1,419 | | -0.129 / -0.401 | -0.75 / -1.49 | | | | |
| CONTROL DOWN 2-4 back OVER | 631 | | -0.718 | -2.06 | -0.766 | -0.666 | 0.552 | 0.575 |

Verdict: nothing passes. On OU25 the drifted runner wins about as often as its price says (0.504 v 0.497). What it does support: nothing at the bar; the 2023 slice and long Unders lean positive, each under t 1.1, with one half negative. Next door: the mirror. Shortened 2-4 points at the off has been the losing side on both markets, so laying it is filed as item 445 (scored only on months before Mar 2023, re-check 12 Nov).

## Re-reads on months no read had used (rule unchanged, window only)
jobs/499_apr23_rereads.sh (Apr 2023), jobs/499_mar23_rereads.sh (Mar 2023), jobs/499_jump_up_unseen_pool.sh (Mar-May 2023 pooled in one read). Every scored line is listed.

| item | scored line | Mar 2023 | Apr 2023 | note |
|---|---|---|---|---|
| 422 | jump-up ONE E1 | n 192 +1.105 t 1.05 | n 191 -0.757 t -0.69 | **Mar-May pooled n 515 +0.220 t 0.33, h1 +0.399, h2 +0.039: over n 300, fails t** |
| 423 | jump-up ONE D5 | n 166 +1.459 | n 158 -1.214 | pooled n 438 +0.187 t 0.25, h2 -0.033 |
| 420 | HT/FT G2 CHEAP back | n 26 -0.364 | n 28 +1.227 | with May n 32 -2.235: three months n 86, all under the bar |
| 421 | YOUTH G1 O2.5 lay | n 28 -1.121 | n 21 +0.445 | May n 13 +2.316 |
| 406 | RULE G0 Y4 O2.5 back | n 14 -10.000 (0 won) | n 16 -0.910 | May-Jul n 9 -4.424 |
| 435 | PEN conceder back MOVED | n 29 -5.525 t -1.95 | (not its window) | 3 winners at median 9.0; open-play control n 320 -3.306; negative, so not pooled with 433/434 |
| 342 | FOUL_HIGH Draw back | 0 trades (1 game matched) | n 5 -2.904 | calendar leagues have under 5 games by March |
| 352 | BOTH home lay / RALLY <2 lay | n 0 / n 1 +9.899 | n 2 -10.000 / n 1 -10.000 | |

Verdict: nothing passes. Item 414's jump-up lead read +1.321 on the 1,500 games whose months chose it; on the 515 games of the three months no read chose, it reads +0.220 at t 0.33. It is no longer a lead at the signal print. What it supports: the favourite leg, Mar-May FAV E1 n 208 +0.885 t 1.24, both halves +0.89, printed and not scored. The next door is item 445 and the Feb 2023 re-read (items 422/423 re-check 14 Nov). This is the second door on the jump-up family (doors: 414 signal, 444 OU25), not yet three, so not dead.

## Sceptical review (problems found, and what was done)
1. My first pooled jump-up figure was a hand-weighted mean with a guessed t; replaced by one computed read (jobs/499_jump_up_unseen_pool.sh), same numbers to 2 dp.
2. Item 444 kept the lowest market_id on 5,660 events that carried two OU25 markets (the same rule as item 414's job). The choice is by id, not outcome, so no direction bias, but coverage is lost; not fixed tonight.
3. Item 444's 2026 line is n 150 only: Aug-Sep 2026 OU25 add no trades (no official results, see the bf-hist-result coverage note), so 2026 is May-Jul.
4. The re-read wrappers print "item 414 reproduced ... n 0", as the CHOSE months are outside the window by design; cosmetic, stated in each job header.
5. Item 70's full scan of bf_hist_other held the disk for several minutes and slowed every lane's queries; worth a lighter count next time.

Scratch files, untracked, not committed: .q_scan_1108.py, .claim_apr23.py, .chk_apr23.py, .add_444.py, .claim_435.py, .add_445.py, .pgact_1108.py.
