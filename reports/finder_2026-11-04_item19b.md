# Finder 2026-11-04 — item 19 (second of that number): tick lead-lag, MO draw v OU25 Under at 0-0

**Verdict: nothing passes.** 0 of 88 lines. The signal trades cost what the no-signal control costs, so there is no lag to take at this friction.

**Source:** not re-run by the Finder. Job 490 failed on a variable clash; the watchman's fixed copy, jobs/403_tick_lead_lag.sh, ran under the runner on 4 Nov (exit 0, 181 s, log /root/pe-queue-logs/403_tick_lead_lag.log). Read from that log.

**Data:** stream_ticks 1 Nov 02:31 – 4 Nov 03:20 UTC, 6.6M ticks in 1,110 paired markets; 553 games with a 0-0 phase, 507 traded, 36,024 rows across all lines. Pairing by event_name in liq_sample. Halves split at the median game, 1 Nov 21:43.

**Limit:** stream_ticks holds no score. 0-0 is a proxy, from the first OPEN in-play tick to the first suspension or a 25% draw jump (median phase 13.9 min, so red cards and VAR checks cut it short). Pilot: about 3 days, and the table rolls.

## Signal v control, lag 0, per £10
| Line | Hold | n | Games | Per £10 | t | t clustered | h1 | h2 | Pass |
|---|---|---|---|---|---|---|---|---|---|
| SHORT back draw | 30 s | 1,938 | 390 | -0.735 | -39.6 | -22.5 | -0.756 | -0.715 | no |
| SHORT back draw | 60 s | 1,938 | 390 | -0.740 | -28.1 | -20.6 | -0.756 | -0.724 | no |
| SHORT back draw, Under lay moved too | 30 s | 1,607 | 367 | -0.703 | -35.4 | -21.7 | -0.703 | -0.702 | no |
| SHORT back draw, Under lay moved too | 60 s | 1,607 | 367 | -0.694 | -24.6 | -19.3 | -0.700 | -0.687 | no |
| CONTROL back draw, no signal | 30 s | 1,738 | 438 | -0.718 | -38.3 | -23.7 | -0.686 | -0.751 | n/a |
| CONTROL back draw, no signal | 60 s | 1,738 | 438 | -0.753 | -30.9 | -22.8 | -0.736 | -0.770 | n/a |
| DRIFT lay draw | 30 s | 938 | 329 | -0.292 | -17.8 | -13.4 | -0.272 | -0.310 | no |
| DRIFT lay draw | 60 s | 938 | 329 | -0.297 | -17.5 | -13.2 | -0.301 | -0.294 | no |
| DRIFT lay draw, Under lay moved too | 30 s | 561 | 259 | -0.277 | -13.7 | -11.1 | -0.251 | -0.300 | no |
| DRIFT lay draw, Under lay moved too | 60 s | 561 | 259 | -0.273 | -12.8 | -10.6 | -0.257 | -0.287 | no |
| CONTROL lay draw, no signal | 30 s | 2,225 | 496 | -0.291 | -25.8 | -16.9 | -0.292 | -0.290 | n/a |
| CONTROL lay draw, no signal | 60 s | 2,225 | 496 | -0.317 | -18.2 | -14.1 | -0.315 | -0.318 | n/a |

## Best cuts by t, every minute and spread cut, lag 0
All are negative, and the two leading cells have only 37–38 trades.

| Line | Hold | Cut | n | Games | Per £10 | t | h1 | h2 |
|---|---|---|---|---|---|---|---|---|
| SHORT, Under lay moved too | 60 s | 70+ min | 37 | 16 | -0.332 | -0.36 | -0.346 | -0.326 |
| SHORT | 60 s | 70+ min | 38 | 16 | -0.480 | -0.53 | -0.346 | -0.535 |
| SHORT, Under lay moved too | 30 s | 70+ min | 37 | 16 | -0.532 | -0.91 | -0.370 | -0.601 |
| SHORT | 30 s | 70+ min | 38 | 16 | -0.636 | -1.09 | -0.405 | -0.730 |
| DRIFT, Under lay moved too | 60 s | 45-70 min | 29 | 17 | -0.157 | -2.54 | -0.096 | -0.231 |

**Reading it:** the best signal line beats its control by about 6p per £10 (-0.694 v -0.753) and the lay side by about 1–4p, far short of the 0.29–0.75 it would have to overcome. Size filters drop many candidate entries (14,448 back, 3,172 lay, control rows included), so these fills are on the deeper books only.

**Log:** the runner's log. This session cannot write to /root/pe-queue-logs, so it does not hold a Finder copy.
