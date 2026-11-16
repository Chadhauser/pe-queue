# Passed cells at a tradable price, full history — 2026-11-16 16:02 UTC

Each bet: last traded price at least 120 s before the off. 'opt' = at that price, 'pess' = one tick worse. 2% commission. £2 a bet. Per £100 staked.

## A. Every cell, no value filter

| cell | bets | pess per £100 | 1st half | 2nd half |
|---|---|---|---|---|
| ALL (pessimistic) | 103920 | £+0.2 | £+0.9 | £-0.6 |
| ALL (optimistic) | 103920 | £+1.4 | £+2.1 | £+0.6 |
| Cricket MATCH_ODDS 0.45-0.50 BACK | 833 | £+1.3 | - | £+1.3 |
| Cricket MATCH_ODDS 0.50-0.55 LAY | 978 | £+4.0 | - | £+4.0 |
| Greyhound Racing WIN 0.50-0.55 LAY | 1015 | £+6.6 | - | £+6.6 |
| Horse Racing WIN 0.50-0.55 LAY | 750 | £+0.9 | - | £+0.9 |
| Soccer BOTH_TEAMS_TO_SCORE 0.30-0.35 BACK | 7293 | £+1.9 | £+4.6 | £-0.9 |
| Soccer BOTH_TEAMS_TO_SCORE 0.65-0.70 LAY | 7344 | £+0.9 | £+1.1 | £+0.7 |
| Soccer CLEAN_SHEET 0.70-0.80 LAY | 2169 | £+0.1 | £+0.1 | - |
| Soccer CORRECT_SCORE 0.20-0.25 BACK | 4330 | £-14.5 | £-2.4 | £-21.3 |
| Soccer DOUBLE_CHANCE 0.25-0.30 LAY | 3419 | £-0.2 | £+4.4 | £-4.8 |
| Soccer FIRST_GOAL_SCORER 0.10-0.15 LAY | 15597 | £+1.9 | £+0.9 | £+2.7 |
| Soccer FIRST_HALF_GOALS_05 0.40-0.45 BACK | 3638 | £+0.5 | £-1.4 | £+3.3 |
| Soccer FIRST_HALF_GOALS_05 0.55-0.60 LAY | 2479 | £+1.4 | £+0.0 | £+3.4 |
| Soccer FIRST_HALF_GOALS_25 0.03-0.06 LAY | 830 | £+25.7 | £+36.2 | £+11.4 |
| Soccer HALF_TIME 0.60-0.65 BACK | 2417 | £+0.2 | £+0.6 | £-0.1 |
| Soccer HALF_TIME 0.65-0.70 LAY | 1290 | £+0.9 | £+3.0 | £-1.5 |
| Soccer HALF_TIME_FULL_TIME 0.30-0.35 BACK | 8450 | £-2.1 | £+0.8 | £-4.7 |
| Soccer HALF_TIME_FULL_TIME 0.35-0.40 BACK | 5616 | £-0.4 | £+0.1 | £-0.8 |
| Soccer HALF_TIME_FULL_TIME 0.40-0.45 LAY | 4057 | £-1.4 | £-3.1 | £+0.2 |
| Soccer HALF_TIME_FULL_TIME 0.45-0.50 BACK | 2751 | £-3.7 | £-6.4 | £-1.3 |
| Soccer OVER_UNDER_45 0.90-1.00 LAY | 28664 | £+0.9 | £+0.7 | £+1.1 |

## B. Value filter (price must beat the cell's fair price by m, pessimistic price)

| m | 1st-half bets | 1st-half per £100 | 2nd-half bets | 2nd-half per £100 (untouched) |
|---|---|---|---|---|
| 0% | 51958 | £+0.9 | 51962 | £-0.6 |
| 1% | 35392 | £+1.0 | 39864 | £-1.1 |
| 2% | 26470 | £+1.7 | 34026 | £-1.6 |
| 4% | 18357 | £+2.0 | 23244 | £-1.7 |

Margin chosen on the first half only: **4%**. Its second-half result above is the honest test.

Chosen rule, second half, by cell:

| cell | bets | per £100 |
|---|---|---|
| Greyhound Racing WIN 0.50-0.55 LAY | 1015 | £+6.6 |
| Horse Racing WIN 0.50-0.55 LAY | 750 | £+0.9 |
| Soccer BOTH_TEAMS_TO_SCORE 0.30-0.35 BACK | 3560 | £-0.9 |
| Soccer CORRECT_SCORE 0.20-0.25 BACK | 2757 | £-21.3 |
| Soccer DOUBLE_CHANCE 0.25-0.30 LAY | 1714 | £-4.8 |
| Soccer FIRST_GOAL_SCORER 0.10-0.15 LAY | 8678 | £+2.7 |
| Soccer FIRST_HALF_GOALS_25 0.03-0.06 LAY | 353 | £+11.4 |
| Soccer HALF_TIME_FULL_TIME 0.35-0.40 BACK | 2962 | £-0.8 |
| Soccer HALF_TIME_FULL_TIME 0.45-0.50 BACK | 1455 | £-1.3 |

History span 01 Jun 2021 to 11 Oct 2026 (64 months). Bets a month under the chosen rule: 646.
