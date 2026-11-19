# The machine — nightly run 2026-11-19 07:08 UTC

## 1. Results

Markets to settle tonight 1207: settled 941, not closed yet 0. Markets with a result in total: 941.

## 2. Real-price cells (bet the price actually on offer, held to the result)

Runner prices at a real touch: 3,962 on 661 settled markets, 2026-11-17 to 2026-11-18; older half before 2026-11-18, newer half from it.
Cells with 30+ bets: 35. Profitable on both halves: 8. (The Verifier gate decides WORKS: n 300+, t 3.5+.)

| cell | bets | £ at £2 | £ per £10 | t | older n / £10 | newer n / £10 | control t |
|---|---|---|---|---|---|---|---|
| HALF_TIME_FULL_TIME 2min LAY p0.00-0.05 intl | 40 | +78.40 | +9.800 | 5.512494249069238e+16 | 18 / +9.800 | 22 / +9.800 | 0.0 |
| HALF_TIME_SCORE 30min LAY p0.00-0.05 intl | 30 | +58.80 | +9.800 | 4.753514738872974e+16 | 19 / +9.800 | 11 / +9.800 | 0.0 |
| CORRECT_SCORE 30min LAY p0.00-0.05 intl | 70 | +137.20 | +9.800 | 2.4441009314046556e+16 | 31 / +9.800 | 39 / +9.800 | 0.0 |
| HALF_TIME_FULL_TIME 30min LAY p0.00-0.05 intl | 46 | +90.16 | +9.800 | 1.9737895624076572e+16 | 23 / +9.800 | 23 / +9.800 | 0.0 |
| CORRECT_SCORE 2min LAY p0.00-0.05 intl | 71 | +139.16 | +9.800 | 1.8463110740299804e+16 | 33 / +9.800 | 38 / +9.800 | 0.0 |
| HALF_TIME_SCORE 2min LAY p0.00-0.05 all | 73 | +67.12 | +4.597 | 0.88 | 26 / +9.800 | 47 / +1.719 | 0.0 |
| CORRECT_SCORE 2min LAY p0.00-0.05 all | 146 | +102.24 | +3.501 | 0.79 | 51 / +9.800 | 95 / +0.120 | -1.24 |
| HALF_TIME_SCORE 2min LAY p0.00-0.05 intl | 32 | +62.72 | +9.800 | 0.0 | 18 / +9.800 | 14 / +9.800 | 0.0 |

## 3. Loser review (what the losers share; the fix is learned on the older half and judged on the newer half)

- **bot v2.2 taker**: 44 settled, £-18.25 (older half £-14.56, newer half £-3.69).
  - losers share hr = 19: 5 bets, £-16.60
  - losers share side = LAY: 37 bets, £-15.62
  - losers share sport = football: 16 bets, £-15.53
  - fix learned on older half: drop sport = football -> older £-14.56 to £+2.30; JUDGED on newer half £-3.69 to £-5.02 -> not adopted
- **small bites**: 1763 settled, £-29.27 (older half £+98.88, newer half £-128.15).
  - losers share cell = DRIFT_FADE k5 H10: 625 bets, £-36.85
  - losers share side = back: 1763 bets, £-29.27
  - losers share liq = 5k-50k: 566 bets, £-28.76
  - fix learned on older half: drop pband = 2-3 -> older £+98.88 to £+109.81; JUDGED on newer half £-128.15 to £-120.05 -> not adopted
- **coherence paper**: 23 settled, £-3.48 (older half £-6.72, newer half £+3.24).
  - losers share side = BACK: 10 bets, £-20.00
  - losers share cell = CORRECT_SCORE cs_aoa: 7 bets, £-14.00
  - fix learned on older half: drop side = BACK -> older £-6.72 to £+5.28; JUDGED on newer half £+3.24 to £+11.24 -> ADOPTED on paper

Adopted fixes tracked forward on the scoreboard: 1.
