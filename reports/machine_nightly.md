# The machine — nightly run 2026-11-20 01:31 UTC

## 1. Results

Markets to settle tonight 1052: settled 1040, not closed yet 0. Markets with a result in total: 2247.

## 2. Real-price cells (bet the price actually on offer, held to the result)

Runner prices at a real touch: 11,225 on 1,668 settled markets, 2026-11-17 to 2026-11-19; older half before 2026-11-18, newer half from it.
Cells with 30+ bets: 84. Profitable on both halves: 8. (The Verifier gate decides WORKS: n 300+, t 3.5+.)

| cell | bets | £ at £2 | £ per £10 | t | older n / £10 | newer n / £10 | control t |
|---|---|---|---|---|---|---|---|
| OVER_UNDER_05 30min BACK p0.95-1.00 all | 31 | +1.49 | +0.240 | 12.52 | 3 / +0.196 | 28 / +0.245 | 0.0 |
| OVER_UNDER_55 30min BACK p0.95-1.00 all | 30 | +1.16 | +0.193 | 10.42 | 2 / +0.147 | 28 / +0.196 | 0.0 |
| HALF_TIME_FULL_TIME 2min LAY p0.05-0.10 all | 99 | +7.49 | +0.378 | 2.5 | 6 / +0.804 | 93 / +0.351 | -3.09 |
| CORRECT_SCORE 30min LAY p0.00-0.05 intl | 154 | +4.07 | +0.132 | 1.97 | 31 / +0.168 | 123 / +0.123 | -2.41 |
| BOTH_TEAMS_TO_SCORE 30min LAY p0.45-0.50 all | 34 | +15.94 | +2.344 | 1.58 | 2 / +8.305 | 32 / +1.971 | -1.92 |
| HALF_TIME_FULL_TIME 30min LAY p0.05-0.10 all | 119 | +4.93 | +0.207 | 1.18 | 7 / +0.779 | 112 / +0.172 | -2.56 |
| CORRECT_SCORE 2min LAY p0.00-0.05 intl | 158 | +2.57 | +0.081 | 0.89 | 33 / +0.179 | 125 / +0.056 | -2.24 |
| HALF_TIME_SCORE 2min LAY p0.05-0.10 all | 77 | +1.87 | +0.121 | 0.45 | 5 / +0.694 | 72 / +0.082 | -0.39 |

## 3. Loser review (what the losers share; the fix is learned on the older half and judged on the newer half)

- **bot v2.2 taker**: 66 settled, £-5.29 (older half £-12.09, newer half £+6.79).
  - losers share hr = 19: 5 bets, £-16.60
  - losers share sport = football: 20 bets, £-15.15
  - losers share mkt = BOTH_TEAMS_TO_SCORE: 5 bets, £-8.02
  - fix learned on older half: drop sport = football -> older £-12.09 to £+0.74; JUDGED on newer half £+6.79 to £+9.12 -> ADOPTED on paper
- **small bites**: 2157 settled, £-114.54 (older half £+102.01, newer half £-216.55).
  - losers share side = back: 2157 bets, £-114.54
  - losers share liq = <5k: 1300 bets, £-103.13
  - losers share mkt = OU25: 1160 bets, £-66.01
  - fix learned on older half: drop pband = 2-3 -> older £+102.01 to £+123.08; JUDGED on newer half £-216.55 to £-201.37 -> not adopted
- **coherence paper**: 34 settled, £-10.72 (older half £-7.32, newer half £-3.40).
  - losers share side = BACK: 16 bets, £-32.00
  - losers share cell = CORRECT_SCORE cs_aoa: 11 bets, £-22.00
  - losers share cell = BOTH_TEAMS_TO_SCORE btts: 5 bets, £-4.20
  - fix learned on older half: drop side = BACK -> older £-7.32 to £+8.68; JUDGED on newer half £-3.40 to £+12.60 -> ADOPTED on paper

Adopted fixes tracked forward on the scoreboard: 2.
