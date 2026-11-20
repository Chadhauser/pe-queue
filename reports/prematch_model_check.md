# The fair-price model before the start: accuracy on eight seasons (accuracy only, never money)

Built 20 Nov 2026 18:58 UTC by /root/pe-sports/grid/prematch.py. Data: api-football results, 29 leagues, 103,500 matches; expected goals from 2023.
Coefficients fitted on 2017-2021 only, so 2022-2025 are out of sample. Lower 'miss score' (log loss) is better; 'base' = always the average home/draw/away split.

| Year | Matches | Result miss score: model | base | Over 2.5 miss score: model | base | Most likely result right | |
|---|---|---|---|---|---|---|---|
| 2018 | 9,651 | 1.0155 | 1.0673 | 0.6862 | 0.6932 | 49.5% | in sample |
| 2019 | 9,718 | 1.0160 | 1.0690 | 0.6821 | 0.6931 | 49.1% | in sample |
| 2020 | 8,024 | 1.0329 | 1.0807 | 0.6858 | 0.6931 | 48.3% | in sample |
| 2021 | 10,698 | 1.0312 | 1.0795 | 0.6863 | 0.6932 | 47.8% | in sample |
| 2022 | 9,676 | 1.0245 | 1.0758 | 0.6868 | 0.6932 | 48.7% | out of sample |
| 2023 | 9,940 | 1.0091 | 1.0676 | 0.6835 | 0.6931 | 50.1% | out of sample |
| 2024 | 9,671 | 1.0210 | 1.0749 | 0.6840 | 0.6930 | 48.5% | out of sample |
| 2025 | 9,988 | 1.0196 | 1.0724 | 0.6852 | 0.6931 | 49.6% | out of sample |

Home win, what the model said against what happened (all years):

| Model said | Matches | Said on average | Happened |
|---|---|---|---|
| 0-10% | 298 | 8.2% | 10.1% |
| 10-20% | 3,235 | 16.3% | 15.0% |
| 20-30% | 10,776 | 25.8% | 26.2% |
| 30-40% | 23,526 | 35.4% | 35.6% |
| 40-50% | 29,294 | 44.9% | 44.1% |
| 50-60% | 19,733 | 54.4% | 53.3% |
| 60-70% | 8,869 | 64.3% | 64.4% |
| 70-80% | 3,222 | 74.1% | 76.9% |
| 80-90% | 856 | 83.4% | 86.4% |
| 90-100% | 23 | 91.3% | 91.3% |

Coefficients used for our tape days (fitted on everything before 1 Jul 2026): home [0.225, 0.259, 0.463], away [0.179, 0.284, 0.443].
The betting market itself is not in this check: the model is only a fact-built opinion; the one test decides whether trading against it pays.

## Against the sharpest closing prices (Pinnacle, from football-data), the same matches
Joined by date, both team names (exact after the alias table) and the final score: 34,492 matches 2018-2026. Result miss score, lower is better:

| Year | Matches | Model | Pinnacle closing price |
|---|---|---|---|
| 2018 | 4,325 | 1.0217 | 0.9891 |
| 2019 | 4,381 | 1.0172 | 0.9899 |
| 2020 | 3,676 | 1.0421 | 1.0147 |
| 2021 | 4,812 | 1.0359 | 1.0023 |
| 2022 | 4,350 | 1.0172 | 0.9983 |
| 2023 | 4,619 | 1.0014 | 0.9782 |
| 2024 | 4,370 | 1.0103 | 0.9853 |
| 2025 | 3,845 | 1.0168 | 0.9960 |
| all | 34,492 | 1.0200 | 0.9938 |

Plain words: the fact-built price is honest (well calibrated, no worse out of sample) but clearly less accurate than the closing market,
every year. Trading where Betfair disagrees with it should mostly lose; the one test below says whether any slice of it pays anyway.
