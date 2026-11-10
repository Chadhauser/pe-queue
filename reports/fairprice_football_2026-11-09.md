# Fair-price engine v1 — FOOTBALL (run 9 Nov 2026, job 544)

209 cells with n>=300 and >=50 each half. Rule: trade toward the in-sample fair price at the closing price, one tick adverse, 2% commission; IS = older half by date, OOS = newer half; control = side at random.

| line | n | £/£10 | t | IS £/£10 | OOS £/£10 | control t |
|---|---|---|---|---|---|---|
| H1 Soccer OVER_UNDER_45 p0.03-0.06 BACK at close (IS rate 0.078 vs implied 0.045 | 2810 | +8.855 | 7.52 | +7.310 | +11.749 | -1.6 |
| H1 Soccer OVER_UNDER_45 p0.90-1.00 LAY at close (IS rate 0.913 vs implied 0.929) | 13967 | +0.081 | 3.14 | +0.062 | +0.110 | -3.69 |
| H1 Soccer OVER_UNDER_45 p0.06-0.10 BACK at close (IS rate 0.090 vs implied 0.080 | 10969 | +0.750 | 2.29 | +0.627 | +0.913 | -1.64 |
| H1 Soccer FIRST_HALF_GOALS_05 p0.55-0.60 LAY at close (IS rate 0.557 vs implied  | 1721 | +0.458 | 2.26 | +0.410 | +0.510 | -1.9 |
| H1 Soccer DRAW_NO_BET p0.06-0.10 LAY at close (IS rate 0.062 vs implied 0.081) | 1025 | +1.661 | 1.68 | +1.921 | +1.427 | -2.32 |
| H1 Soccer DRAW_NO_BET p0.03-0.06 LAY at close (IS rate 0.039 vs implied 0.046) | 628 | +2.649 | 1.64 | +1.513 | +3.441 | -0.34 |
| H1 Soccer DOUBLE_CHANCE p0.10-0.15 LAY at close (IS rate 0.125 vs implied 0.127) | 445 | +1.844 | 1.58 | -0.512 | +3.911 | 0.15 |
| H1 Soccer CORRECT_SCORE p0.20-0.25 BACK at close (IS rate 0.251 vs implied 0.222 | 1109 | +0.877 | 1.56 | +0.801 | +0.936 | -2.09 |
| H1 Soccer FIRST_HALF_GOALS_05 p0.40-0.45 BACK at close (IS rate 0.444 vs implied | 1758 | +0.432 | 1.56 | +0.355 | +0.516 | -1.54 |
| H1 Soccer CORRECT_SCORE p0.30-0.35 LAY at close (IS rate 0.262 vs implied 0.322) | 328 | +1.113 | 1.45 | +1.699 | +0.670 | -0.43 |
| H1 Soccer MATCH_ODDS p0.00-0.03 BACK at close (IS rate 0.031 vs implied 0.019) | 1262 | +3.416 | 1.36 | +5.713 | +1.438 | -0.16 |
| H1 Soccer BOTH_TEAMS_TO_SCORE p0.65-0.70 LAY at close (IS rate 0.648 vs implied  | 4326 | +0.139 | 1.31 | +0.234 | +0.068 | -1.8 |
| H1 Soccer OVER_UNDER_35 p0.55-0.60 LAY at close (IS rate 0.570 vs implied 0.576) | 7815 | +0.094 | 0.98 | +0.033 | +0.151 | -1.22 |
| H1 Soccer OVER_UNDER_25 p0.30-0.35 LAY at close (IS rate 0.316 vs implied 0.328) | 8183 | +0.150 | 0.96 | +0.173 | +0.129 | -2.63 |
| H1 Soccer DRAW_NO_BET p0.90-1.00 BACK at close (IS rate 0.953 vs implied 0.937) | 1941 | +0.048 | 0.95 | +0.046 | +0.049 | -2.53 |
| H1 Soccer HALF_TIME p0.55-0.60 BACK at close (IS rate 0.619 vs implied 0.573) | 1538 | +0.190 | 0.88 | +0.602 | -0.162 | 0.61 |
| H1 Soccer HALF_TIME p0.60-0.65 BACK at close (IS rate 0.642 vs implied 0.621) | 949 | +0.209 | 0.85 | +0.156 | +0.254 | -0.47 |
| H1 Soccer DRAW_NO_BET p0.55-0.60 LAY at close (IS rate 0.569 vs implied 0.575) | 4795 | +0.103 | 0.84 | +0.041 | +0.171 | -1.09 |
| H1 Soccer HALF_TIME p0.03-0.06 BACK at close (IS rate 0.058 vs implied 0.049) | 398 | +1.979 | 0.82 | +1.674 | +2.208 | 0.85 |
| H1 Soccer DRAW_NO_BET p0.50-0.55 LAY at close (IS rate 0.509 vs implied 0.524) | 4932 | +0.108 | 0.81 | +0.214 | +0.002 | -1.93 |
| H1 Soccer MATCH_ODDS p0.03-0.06 LAY at close (IS rate 0.045 vs implied 0.046) | 2488 | +0.716 | 0.79 | +0.059 | +1.292 | -0.3 |
| H1 Soccer FIRST_HALF_GOALS_15 p0.50-0.55 LAY at close (IS rate 0.514 vs implied  | 7590 | +0.085 | 0.79 | +0.114 | +0.061 | 0.87 |
| H1 Soccer OVER_UNDER_35 p0.50-0.55 LAY at close (IS rate 0.517 vs implied 0.524) | 6954 | +0.077 | 0.68 | +0.063 | +0.090 | -3.3 |
| H1 Soccer HALF_TIME p0.65-0.70 LAY at close (IS rate 0.651 vs implied 0.673) | 497 | +0.212 | 0.68 | +0.258 | +0.166 | 0.34 |
| H1 Soccer DOUBLE_CHANCE p0.25-0.30 LAY at close (IS rate 0.251 vs implied 0.277) | 1478 | +0.263 | 0.63 | +0.685 | -0.131 | -0.16 |
| H1 Soccer OVER_UNDER_35 p0.25-0.30 LAY at close (IS rate 0.266 vs implied 0.275) | 12042 | +0.088 | 0.59 | +0.095 | +0.080 | -3.62 |
| H1 Soccer OVER_UNDER_15 p0.55-0.60 LAY at close (IS rate 0.546 vs implied 0.581) | 943 | +0.158 | 0.58 | +0.518 | -0.230 | -1.94 |
| H1 Soccer OVER_UNDER_15 p0.06-0.10 BACK at close (IS rate 0.092 vs implied 0.086 | 2072 | +0.374 | 0.52 | +0.006 | +0.605 | -1.43 |
| H1 Soccer HALF_TIME_FULL_TIME p0.35-0.40 BACK at close (IS rate 0.399 vs implied | 1735 | +0.157 | 0.52 | +0.336 | -0.005 | -0.96 |
| H1 Soccer FIRST_GOAL_SCORER p0.10-0.15 LAY at close (IS rate 0.100 vs implied 0. | 340 | +0.728 | 0.52 | +1.607 | -0.053 | -0.75 |
| H1 Soccer FIRST_HALF_GOALS_25 p0.06-0.10 LAY at close (IS rate 0.084 vs implied  | 8314 | +0.168 | 0.47 | -0.150 | +0.523 | -0.48 |
| H1 Soccer BOTH_TEAMS_TO_SCORE p0.30-0.35 BACK at close (IS rate 0.352 vs implied | 4248 | +0.094 | 0.44 | +0.336 | -0.087 | -1.36 |
| H1 Soccer HALF_TIME_SCORE p0.30-0.35 LAY at close (IS rate 0.310 vs implied 0.32 | 3175 | +0.112 | 0.44 | +0.372 | -0.265 | 0.02 |
| H1 Soccer FIRST_HALF_GOALS_05 p0.65-0.70 LAY at close (IS rate 0.675 vs implied  | 16688 | +0.023 | 0.43 | -0.061 | +0.116 | -2.3 |
| H1 Soccer FIRST_HALF_GOALS_25 p0.70-0.80 LAY at close (IS rate 0.754 vs implied  | 5925 | +0.030 | 0.42 | +0.057 | +0.007 | 0.85 |
| H1 Soccer OVER_UNDER_05 p0.00-0.03 LAY at close (IS rate 0.022 vs implied 0.022) | 6129 | +0.308 | 0.34 | +0.275 | +0.332 | -1.6 |
| H1 Soccer OVER_UNDER_25 p0.80-0.90 LAY at close (IS rate 0.803 vs implied 0.834) | 980 | +0.046 | 0.32 | +0.267 | -0.104 | -0.08 |
| H1 Soccer HALF_TIME_FULL_TIME p0.40-0.45 LAY at close (IS rate 0.417 vs implied  | 1141 | +0.097 | 0.29 | +0.150 | +0.052 | -0.02 |
| H1 Soccer HALF_TIME_FULL_TIME p0.15-0.20 LAY at close (IS rate 0.164 vs implied  | 19590 | +0.043 | 0.27 | +0.358 | -0.304 | -2.9 |
| H1 Soccer DRAW_NO_BET p0.65-0.70 LAY at close (IS rate 0.671 vs implied 0.674) | 4048 | +0.027 | 0.25 | +0.006 | +0.050 | -0.24 |

## Passed cells (the bot quotes only these)

| sport | market | band | side | n IS | n OOS | edge IS | edge OOS |
|---|---|---|---|---|---|---|---|
| Soccer | BOTH_TEAMS_TO_SCORE | 0.30-0.35 | BACK | 1814 | 2434 | +0.021 | +0.008 |
| Soccer | BOTH_TEAMS_TO_SCORE | 0.65-0.70 | LAY | 1856 | 2470 | -0.021 | -0.008 |
| Soccer | CORRECT_SCORE | 0.20-0.25 | BACK | 482 | 627 | +0.029 | +0.035 |
| Soccer | DRAW_NO_BET | 0.06-0.10 | LAY | 486 | 539 | -0.019 | -0.015 |
| Soccer | DRAW_NO_BET | 0.20-0.25 | BACK | 1353 | 1421 | +0.011 | +0.010 |
| Soccer | DRAW_NO_BET | 0.90-1.00 | BACK | 852 | 1089 | +0.016 | +0.015 |
| Soccer | FIRST_HALF_GOALS_05 | 0.40-0.45 | BACK | 915 | 843 | +0.028 | +0.034 |
| Soccer | FIRST_HALF_GOALS_05 | 0.55-0.60 | LAY | 896 | 825 | -0.027 | -0.035 |
| Soccer | FIRST_HALF_GOALS_15 | 0.45-0.50 | BACK | 3225 | 3943 | +0.011 | +0.008 |
| Soccer | FIRST_HALF_GOALS_15 | 0.50-0.55 | LAY | 3431 | 4159 | -0.011 | -0.008 |
| Soccer | FIRST_HALF_GOALS_25 | 0.20-0.25 | BACK | 2125 | 2360 | +0.011 | +0.010 |
| Soccer | HALF_TIME | 0.60-0.65 | BACK | 438 | 511 | +0.021 | +0.027 |
| Soccer | HALF_TIME_FULL_TIME | 0.30-0.35 | BACK | 1237 | 1301 | +0.012 | +0.015 |
| Soccer | HALF_TIME_FULL_TIME | 0.35-0.40 | BACK | 824 | 911 | +0.026 | +0.016 |
| Soccer | HALF_TIME_FULL_TIME | 0.45-0.50 | BACK | 453 | 469 | +0.029 | +0.007 |
| Soccer | OVER_UNDER_25 | 0.30-0.35 | LAY | 3936 | 4247 | -0.012 | -0.011 |
| Soccer | OVER_UNDER_25 | 0.65-0.70 | BACK | 4026 | 4325 | +0.012 | +0.010 |
| Soccer | OVER_UNDER_45 | 0.03-0.06 | BACK | 1832 | 978 | +0.033 | +0.053 |
| Soccer | OVER_UNDER_45 | 0.90-1.00 | LAY | 8241 | 5726 | -0.016 | -0.019 |
