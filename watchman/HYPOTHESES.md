# Hypothesis ledger — one line per idea: date | source | idea | status | result (per £10, n, halves)
2026-11-03 | c structural | racing PLACE vs WIN Harville mispricing (461) | DONE | nothing passes; best t 1.31; place BSP calibrated
2026-11-03 | d untested | FH05/FH15 overs by minute at 0-0/1 goal (462) | DONE | nothing passes; best +0.12 n 5,808 t 2.39; 3-min goal buffer fakes t 6
2026-11-03 | b Webb | racing morning money, morning WAP -> BSP (463) | DONE | WAP-only numeric pass (+0.20 n 29,400 t 20.5), dies at 3-5 ticks of spread; not a print
2026-11-03 | c structural | kick-off FLB by country, full MO tape (464) | DONE | nothing passes; best t 3.25 known-only, negative with unknown=loss
2026-11-03 | b Webb (from 463) | morning money at the real morning touch (needs morning book recorder) | TODO (item 17) | —
2026-11-03 | a moves (from 463) | low-money drifters lay into the off on stream_ticks (pilot, 465) | DONE | nothing passes; no drift in the last 10 min; LAY −0.07…−0.13 (spread), n 70–288 per band
2026-11-03 | a moves (liq_sample, 1-2 Nov, 412 games) | DNB lags MO: DNB-implied prob closes only ~11% of its gap to the MO-implied fair per minute; a 6-pt gap moves 1.3 pts vs ~6 pts half-spread -> crossing loses; a resting order at the MO-fair DNB price might not, but stream_ticks has no DNB (needs DNB on the stream recorder) | BLOCKED (data) | —
2026-11-03 | a moves (from the DNB~MO lag above; stream_ticks) | tick-level lead-lag MO DRAW vs OU25 UNDER at 0-0 in-play: when UNDER shortens >=2 ticks in 10 s and the draw has not moved, back the draw at the touch, exit +30/+60 s at the touch | TODO (item 19) | —
2026-11-03 | queue 0e (bookie-shaped) | related-market arb inside a game, LP worst-outcome margin, 5 pairs on liq_sample (466) | DONE | nothing passes; exec at next snapshot -2.71/£10 n 175 t -6.1 h1 -4.08 h2 -1.45; CS 'arbs' are post-goal stale books
