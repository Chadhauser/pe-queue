# Fair price v2 — learned model, 2026-11-16 18:27 UTC

Price 2 min before the off plus its moves (3 h, 60, 30, 10 min), country, hour, weekday, runners, rank, market type. Per sport: train oldest 50%,
choose the margin on the next 25%, judge on the newest 25% (unseen). Tradable price = one tick worse than the last trade. 2% commission, £2 a bet.

| sport | runners | model log loss vs market (unseen) | margin chosen | unseen bets | unseen per £100 | unseen 1st half | unseen 2nd half |
|---|---|---|---|---|---|---|---|
| Cricket | 8238 | 0.6427 vs 0.7784 (model better) | 10% | 1366 | £+1.0 | £-2.1 | £+4.1 |
| Horse Racing | 9360 | 0.3260 vs 0.2868 (market better) | 10% | 2105 | £-20.2 | £-12.5 | £-27.9 |
| Soccer | 835608 | 0.2819 vs 0.4112 (model better) | 10% | 47209 | £-0.2 | £+0.1 | £-0.4 |

Unseen quarter, by market type (bets, per £100):

- Cricket MATCH_ODDS: 1366 bets, £+1.0
- Horse Racing WIN: 2105 bets, £-20.2
- Soccer CORRECT_SCORE: 3709 bets, £+19.9
- Soccer FIRST_GOAL_SCORER: 14195 bets, £-25.5
- Soccer HALF_TIME_FULL_TIME: 1222 bets, £-18.1
- Soccer HALF_TIME_SCORE: 1314 bets, £-1.6
- Soccer TO_SCORE: 26682 bets, £+11.3

Lower log loss = better probabilities. If the model is not better than the market on the unseen quarter, any profit above is luck.
