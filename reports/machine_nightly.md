# The machine — nightly run 2026-11-19 07:10 UTC

## 1. Results

Markets to settle tonight 266: settled 266, not closed yet 0. Markets with a result in total: 1207.

## 2. Real-price cells (bet the price actually on offer, held to the result)

Runner prices at a real touch: 4,641 on 782 settled markets, 2026-11-17 to 2026-11-18; older half before 2026-11-18, newer half from it.
Cells with 30+ bets: 43. Profitable on both halves: 8. (The Verifier gate decides WORKS: n 300+, t 3.5+.)

| cell | bets | £ at £2 | £ per £10 | t | older n / £10 | newer n / £10 | control t |
|---|---|---|---|---|---|---|---|
| CORRECT_SCORE 2min LAY p0.00-0.05 intl | 80 | +2.93 | +0.183 | 11.66 | 33 / +0.179 | 47 / +0.186 | 0.0 |
| CORRECT_SCORE 30min LAY p0.00-0.05 intl | 79 | +2.75 | +0.174 | 11.23 | 31 / +0.168 | 48 / +0.178 | 0.0 |
| HALF_TIME_FULL_TIME 2min LAY p0.00-0.05 intl | 42 | +1.52 | +0.180 | 10.67 | 18 / +0.139 | 24 / +0.212 | 0.0 |
| HALF_TIME_FULL_TIME 30min LAY p0.00-0.05 intl | 48 | +1.57 | +0.164 | 10.44 | 23 / +0.140 | 25 / +0.186 | 0.0 |
| HALF_TIME_SCORE 30min LAY p0.00-0.05 intl | 33 | +1.11 | +0.168 | 6.93 | 19 / +0.177 | 14 / +0.154 | 0.0 |
| HALF_TIME_SCORE 2min LAY p0.00-0.05 intl | 35 | +1.19 | +0.170 | 6.87 | 18 / +0.161 | 17 / +0.179 | 0.0 |
| HALF_TIME_FULL_TIME 2min LAY p0.05-0.10 all | 32 | +1.85 | +0.290 | 0.87 | 6 / +0.804 | 26 / +0.171 | -1.3 |
| HALF_TIME_FULL_TIME 30min LAY p0.05-0.10 all | 49 | +1.23 | +0.126 | 0.42 | 7 / +0.779 | 42 / +0.017 | -3.06 |

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
