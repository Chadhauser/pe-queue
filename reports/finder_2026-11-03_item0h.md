# Finder 2026-11-03: item 0h, pre-match steam continuation (jobs/469)

**Data:** stream_ticks football MO_PRE, pre-off, OPEN, 31 Oct 02:30 to 3 Nov 22:13 UTC (3.8 days, the whole rolling table). 3,045,549 ticks, 814 markets, 2,442 runners, 20,188 entries. Halves split at 1 Nov 13:30 UTC. The feed starts at T-2h, so a 15-minute look-back fires from T-105 at the earliest, and the volume test (needs t-1800) from T-90.

**Rule:** back_px moved >= 3% or >= 5% against the book 15 minutes earlier. "v" = runner volume in the last 15 min > the 15 min before. One entry per runner per signal per time-to-KO band (5-30, 30-60, 60-105 min); ONE = first per game. Back at back_px -1 tick, lay out at lay_px +1 tick (exact ladder), 2% commission, £10 stake. DRIFT is the lay mirror at £10 liability. CTRL is the same trade with |move| < 3%.

**Exits:** KO = last pre-off tick. P15 = first tick at or after +15 min, else the last pre-off tick. No trade dropped: 11 entries with no later tick exit at their own book (full spread + 2 ticks). Pre-off positions never settle, so the settled-market rule does not apply.

## Headline (£ per £10; short/long = share of entries whose mid shortened/lengthened by exit; logmv + = shortened)
| Line | Exit | n | Games | per £10 | t | tc | h1 | h2 | short | long | logmv | Pass |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| STEAM3v (the item's rule) | KO | 1,222 | 531 | -0.758 | -21.0 | -15.6 | -0.794 | -0.726 | 54.5% | 38.7% | +0.006 | no |
| STEAM3v | P15 | 1,222 | 531 | -0.698 | -25.7 | -18.8 | -0.718 | -0.679 | 55.4% | 32.2% | +0.013 | no |
| STEAM3v ONE per game | KO | 531 | 531 | -0.721 | -11.4 | -11.4 | -0.799 | -0.641 | 56.7% | 37.1% | +0.002 | no |
| STEAM3v spread <= 2 ticks | KO | 526 | 305 | -0.648 | -14.9 | -11.1 | -0.674 | -0.623 | 48.1% | 43.2% | -0.002 | no |
| STEAM5v | KO | 718 | 383 | -0.805 | -14.9 | -12.3 | -0.825 | -0.786 | 57.9% | 37.9% | +0.007 | no |
| STEAM3 no volume test | KO | 1,620 | 612 | -1.019 | -23.5 | -16.3 | -1.070 | -0.973 | 53.0% | 39.9% | +0.002 | no |
| Control back | KO | 6,132 | 772 | -0.824 | -51.0 | -25.2 | -0.829 | -0.818 | 46.3% | 46.6% | -0.003 | n/a |
| Control back spread <= 2 ticks | P15 | 2,995 | 644 | -0.538 | -64.5 | -49.7 | -0.532 | -0.543 | 34.6% | 32.8% | 0.000 | n/a |
| DRIFT3v lay | KO | 1,441 | 565 | -0.234 | -14.7 | -11.7 | -0.235 | -0.234 | 39.1% | 56.3% | -0.028 | no |
| DRIFT3v spread <= 2 ticks | KO | 1,014 | 487 | -0.189 | -11.7 | -9.5 | -0.187 | -0.192 | 39.0% | 55.6% | -0.026 | no |
| Control lay | KO | 6,132 | 772 | -0.391 | -38.4 | -18.3 | -0.410 | -0.371 | 46.3% | 46.6% | -0.003 | n/a |

## Top 15 by t, all non-control cells (all n < 150: fails the n test, every mean negative)
| Cell | Exit | n | per £10 | t | h1 | h2 |
|---|---|---|---|---|---|---|
| STEAM5v px 2-3 ttk 60-105 | KO | 25 | -0.064 | -0.25 | -0.194 | +0.010 |
| STEAM3v px 2-3 ttk 60-105 | KO | 35 | -0.095 | -0.48 | -0.358 | +0.079 |
| STEAM5v px <2 ttk 60-105 | P15 | 18 | -0.466 | -1.06 | -0.268 | -0.714 |
| STEAM3v px <2 ttk 60-105 | P15 | 28 | -0.321 | -1.10 | -0.154 | -0.514 |
| DRIFT3v px 2-3 ttk 30-60 | KO | 91 | -0.104 | -1.49 | -0.182 | -0.043 |
| STEAM3v px <2 ttk 60-105 | KO | 28 | -0.457 | -1.56 | -0.346 | -0.584 |
| STEAM5v px <2 ttk 60-105 | KO | 18 | -0.695 | -1.57 | -0.526 | -0.907 |
| STEAM5v px 2-3 ttk 60-105 | P15 | 25 | -0.170 | -1.64 | -0.253 | -0.123 |
| DRIFT3v px <2 ttk 30-60 | KO | 64 | -0.220 | -1.73 | -0.366 | -0.083 |
| DRIFT3 px 10+ ttk 05-30 | P15 | 73 | -0.257 | -2.10 | -0.370 | -0.148 |
| STEAM5v px 2-3 ttk 30-60 | KO | 56 | -0.311 | -2.13 | -0.170 | -0.425 |
| STEAM5 px 2-3 ttk 60-105 | KO | 36 | -0.793 | -2.16 | -1.458 | -0.262 |
| STEAM3v px 2-3 ttk 60-105 | P15 | 35 | -0.167 | -2.20 | -0.288 | -0.086 |
| DRIFT3 px 10+ ttk 05-30 | KO | 73 | -0.275 | -2.24 | -0.373 | -0.180 |
| DRIFT3v px 2-3 ttk 30-60 | P15 | 64 | -0.239 | -2.36 | -0.325 | -0.158 |

**Best with n >= 300:** DRIFT3 px 2-3 KO, n 369, -£0.410, t -5.7. Nothing positive.

**Survivors: 0 of 436 cells (176 had n >= 300).**

## Verdict: nothing passes
Steam does not pay. The item's rule loses -£0.76/£10 to KO (n 1,222, 531 games, t -21, h1 -0.79, h2 -0.73), no better than the control's -£0.82. The 54.5% v 38.7% continuation is not usable: on tight books it nearly vanishes (48.1% v 43.2%, mean move -0.2%), so most of it is wide books closing, which you cannot capture by crossing them.

Drifters are the one real move: they keep lengthening (56% v 39%, about -2.8% to KO, control -0.3%). The lay still loses -£0.23, because the move is smaller than the cost of crossing. Own new item 34 tests the passive version.

**Caveats:** steam and drift per-£10 figures are not comparable with each other (back = £10 stake, lay = £10 liability, so a much smaller stake at these prices); compare each with its own control. Entry size is checked only in the sz>=10 cells, and exit size never; both can only flatter these results. Three runners and three bands per game inflate t, so tc is shown. The engine's friction agrees with the queue's separately measured round trip (control -£0.538 v -£0.52, item 29).

**Re-run:** n is not the constraint (STEAM3v accrues 320 entries a day), but the table appears to roll at ~3.8 days, so n will not accumulate. Re-run 7 Nov for a window with no overlap, purely as an out-of-sample check.

**Run notes:** first run stopped on its own unit check (my expected value used 5.8 for one tick below 6.0; the ladder gives 5.9, as the code did). Corrected by hand, re-run. Job 465's `tick()` overstates the adverse tick when a price sits exactly on a band edge; check other jobs that copied it. Log kept in the harness task file, not /root/pe-queue-logs (writing there needed approval). FINDER_LANE was unreadable for the same reason, so this run took the top TODO.
