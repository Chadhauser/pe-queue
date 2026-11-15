# Results backfill and engine, every sport — 2026-11-15 22:39 UTC

## Backfill
- Cricket: markets re-read 5237, result rows 0 -> 18902, result markets 9370, of which 4685 join to a price market
- Tennis: markets re-read 23166, result rows 0 -> 87192, result markets 43596, of which 21785 join to a price market
- Horse Racing: markets re-read 14406, result rows 0 -> 257372, result markets 27978, of which 13989 join to a price market
- Greyhound Racing: markets re-read 19559, result rows 0 -> 209988, result markets 38406, of which 16609 join to a price market

## Engine
```
   ('Soccer', 'HALF_TIME_FULL_TIME', Decimal('0.45'), Decimal('0.5'), 'BACK', 681, Decimal('0.0334'), Decimal('0.0138'))
   ('Soccer', 'OVER_UNDER_45', Decimal('0.9'), Decimal('1.0001'), 'LAY', 12341, Decimal('-0.0154'), Decimal('-0.0171'))
verifier done 15:52
  print(f"{datetime.datetime.utcnow():%Y-%m-%d %H:%M} passed cells: {n} (fair_factor BETWEEN 0.7 AND 1.3 enforced)"); [print("  ",r) for r in c.fetchall()]
cells dropped by the replay (negative on real books): 0
2026-11-15 22:39 passed cells: 23 (fair_factor BETWEEN 0.7 AND 1.3 enforced)
   ('Cricket', 'MATCH_ODDS', Decimal('0.45'), Decimal('0.5'), 'BACK', 372, Decimal('0.0217'), Decimal('0.0108'))
   ('Cricket', 'MATCH_ODDS', Decimal('0.5'), Decimal('0.55'), 'LAY', 410, Decimal('-0.0172'), Decimal('-0.0079'))
   ('Greyhound Racing', 'WIN', Decimal('0.5'), Decimal('0.55'), 'LAY', 387, Decimal('-0.0641'), Decimal('-0.0315'))
   ('Horse Racing', 'WIN', Decimal('0.5'), Decimal('0.55'), 'LAY', 348, Decimal('-0.0262'), Decimal('-0.0244'))
   ('Soccer', 'BOTH_TEAMS_TO_SCORE', Decimal('0.3'), Decimal('0.35'), 'BACK', 2400, Decimal('0.0206'), Decimal('0.0069'))
   ('Soccer', 'BOTH_TEAMS_TO_SCORE', Decimal('0.65'), Decimal('0.7'), 'LAY', 2460, Decimal('-0.0197'), Decimal('-0.0073'))
   ('Soccer', 'CLEAN_SHEET', Decimal('0.7'), Decimal('0.8'), 'LAY', 576, Decimal('-0.0169'), Decimal('-0.0058'))
   ('Soccer', 'CORRECT_SCORE', Decimal('0.2'), Decimal('0.25'), 'BACK', 765, Decimal('0.0233'), Decimal('0.0135'))
   ('Soccer', 'DOUBLE_CHANCE', Decimal('0.25'), Decimal('0.3'), 'LAY', 1054, Decimal('-0.0195'), Decimal('-0.0067'))
   ('Soccer', 'FIRST_GOAL_SCORER', Decimal('0.1'), Decimal('0.15'), 'LAY', 430, Decimal('-0.0221'), Decimal('-0.0162'))
   ('Soccer', 'FIRST_HALF_GOALS_05', Decimal('0.4'), Decimal('0.45'), 'BACK', 1545, Decimal('0.011'), Decimal('0.0263'))
   ('Soccer', 'FIRST_HALF_GOALS_05', Decimal('0.55'), Decimal('0.6'), 'LAY', 1520, Decimal('-0.0106'), Decimal('-0.0276'))
   ('Soccer', 'FIRST_HALF_GOALS_25', Decimal('0.03'), Decimal('0.06'), 'LAY', 407, Decimal('-0.0143'), Decimal('-0.0081'))
   ('Soccer', 'HALF_TIME', Decimal('0.6'), Decimal('0.65'), 'BACK', 599, Decimal('0.016'), Decimal('0.0196'))
   ('Soccer', 'HALF_TIME', Decimal('0.65'), Decimal('0.7'), 'LAY', 342, Decimal('-0.0288'), Decimal('-0.0147'))
   ('Soccer', 'HALF_TIME_FULL_TIME', Decimal('0.3'), Decimal('0.35'), 'BACK', 1818, Decimal('0.0145'), Decimal('0.0085'))
   ('Soccer', 'HALF_TIME_FULL_TIME', Decimal('0.35'), Decimal('0.4'), 'BACK', 1227, Decimal('0.0203'), Decimal('0.023'))
   ('Soccer', 'HALF_TIME_FULL_TIME', Decimal('0.4'), Decimal('0.45'), 'LAY', 814, Decimal('-0.0108'), Decimal('-0.0168'))
   ('Soccer', 'HALF_TIME_FULL_TIME', Decimal('0.45'), Decimal('0.5'), 'BACK', 681, Decimal('0.0334'), Decimal('0.0138'))
   ('Soccer', 'OVER_UNDER_45', Decimal('0.9'), Decimal('1.0001'), 'LAY', 12341, Decimal('-0.0154'), Decimal('-0.0171'))
   ('Tennis', 'MATCH_ODDS', Decimal('0.2'), Decimal('0.25'), 'LAY', 909, Decimal('-0.0149'), Decimal('-0.0292'))
   ('Tennis', 'MATCH_ODDS', Decimal('0.4'), Decimal('0.45'), 'LAY', 1678, Decimal('-0.0116'), Decimal('-0.006'))
   ('Tennis', 'MATCH_ODDS', Decimal('0.55'), Decimal('0.6'), 'BACK', 1676, Decimal('0.0111'), Decimal('0.0057'))

```
### Cricket
```
RESULT {"name": "H1 Cricket MATCH_ODDS p0.40-0.45 LAY at close (IS rate 0.406 vs implied 0.424)", "n": 918, "mean_per10": -0.19, "t": -0.5, "is_mean": 0.319, "is_t": 0.58, "oos_mean": -0.647, "oos_t":
RESULT {"name": "H1 Cricket MATCH_ODDS p0.45-0.50 BACK at close (IS rate 0.495 vs implied 0.473)", "n": 855, "mean_per10": -0.003, "t": -0.01, "is_mean": 0.105, "is_t": 0.2, "oos_mean": -0.086, "oos_t
RESULT {"name": "H1 Cricket MATCH_ODDS p0.50-0.55 LAY at close (IS rate 0.507 vs implied 0.525)", "n": 937, "mean_per10": 0.191, "t": 0.62, "is_mean": 0.327, "is_t": 0.71, "oos_mean": 0.085, "oos_t": 
RESULT {"name": "H1 Cricket MATCH_ODDS p0.55-0.60 BACK at close (IS rate 0.594 vs implied 0.576)", "n": 920, "mean_per10": -0.284, "t": -1.02, "is_mean": 0.063, "is_t": 0.16, "oos_mean": -0.596, "oos_
RESULT {"name": "H1 Cricket MATCH_ODDS p0.60-0.65 LAY at close (IS rate 0.599 vs implied 0.625)", "n": 664, "mean_per10": -0.161, "t": -0.54, "is_mean": 0.377, "is_t": 0.9, "oos_mean": -0.722, "oos_t"
RESULT {"name": "H1 Cricket MATCH_ODDS p0.65-0.70 BACK at close (IS rate 0.676 vs implied 0.674)", "n": 478, "mean_per10": -0.035, "t": -0.11, "is_mean": -0.212, "is_t": -0.49, "oos_mean": 0.158, "oos
RESULT {"name": "H1 Cricket MATCH_ODDS p0.70-0.80 BACK at close (IS rate 0.782 vs implied 0.744)", "n": 504, "mean_per10": 0.367, "t": 1.51, "is_mean": 0.306, "is_t": 0.94, "oos_mean": 0.446, "oos_t":
RESULT {"name": "H1 Cricket MATCH_ODDS p0.80-0.90 BACK at close (IS rate 0.887 vs implied 0.846)", "n": 334, "mean_per10": 0.515, "t": 2.77, "is_mean": 0.298, "is_t": 1.12, "oos_mean": 0.82, "oos_t": 
RESULT {"name": "H1 Cricket MATCH_ODDS p0.90-1.00 BACK at close (IS rate 0.975 vs implied 0.947)", "n": 325, "mean_per10": 0.119, "t": 1.18, "is_mean": 0.195, "is_t": 1.48, "oos_mean": 0.046, "oos_t":
  Cricket/MATCH_ODDS: 8313 runner-rows, 4123 books, cells 11, 29s
cells reported 11 | runner-rows 8313 | multi-line types left out (loader has no handicap value): []
NEXT DOOR (pre-registered): loader captures the runner handicap `hc` so AH/goal-line/handicap books settle (H1d); in-play bands for every sport (H1b extended).
```
### Tennis
```
RESULT {"name": "H1 Tennis MATCH_ODDS p0.40-0.45 LAY at close (IS rate 0.414 vs implied 0.425)", "n": 3283, "mean_per10": 0.062, "t": 0.31, "is_mean": 0.138, "is_t": 0.49, "oos_mean": -0.017, "oos_t":
RESULT {"name": "H1 Tennis MATCH_ODDS p0.45-0.50 BACK at close (IS rate 0.488 vs implied 0.474)", "n": 2780, "mean_per10": -0.189, "t": -0.97, "is_mean": 0.027, "is_t": 0.1, "oos_mean": -0.417, "oos_t
RESULT {"name": "H1 Tennis MATCH_ODDS p0.50-0.55 LAY at close (IS rate 0.512 vs implied 0.524)", "n": 2938, "mean_per10": -0.046, "t": -0.26, "is_mean": 0.147, "is_t": 0.61, "oos_mean": -0.249, "oos_t
RESULT {"name": "H1 Tennis MATCH_ODDS p0.55-0.60 BACK at close (IS rate 0.586 vs implied 0.575)", "n": 3280, "mean_per10": -0.06, "t": -0.41, "is_mean": -0.037, "is_t": -0.18, "oos_mean": -0.084, "oos
RESULT {"name": "H1 Tennis MATCH_ODDS p0.60-0.65 LAY at close (IS rate 0.602 vs implied 0.624)", "n": 3151, "mean_per10": -0.207, "t": -1.52, "is_mean": 0.275, "is_t": 1.42, "oos_mean": -0.705, "oos_t
RESULT {"name": "H1 Tennis MATCH_ODDS p0.65-0.70 BACK at close (IS rate 0.677 vs implied 0.675)", "n": 2744, "mean_per10": 0.036, "t": 0.28, "is_mean": -0.14, "is_t": -0.75, "oos_mean": 0.208, "oos_t"
RESULT {"name": "H1 Tennis MATCH_ODDS p0.70-0.80 BACK at close (IS rate 0.748 vs implied 0.745)", "n": 3984, "mean_per10": -0.113, "t": -1.25, "is_mean": -0.129, "is_t": -1.01, "oos_mean": -0.097, "oo
RESULT {"name": "H1 Tennis MATCH_ODDS p0.80-0.90 LAY at close (IS rate 0.832 vs implied 0.843)", "n": 2449, "mean_per10": -0.103, "t": -1.2, "is_mean": 0.065, "is_t": 0.51, "oos_mean": -0.267, "oos_t"
RESULT {"name": "H1 Tennis MATCH_ODDS p0.90-1.00 BACK at close (IS rate 0.965 vs implied 0.938)", "n": 1557, "mean_per10": -0.061, "t": -1.02, "is_mean": 0.171, "is_t": 2.24, "oos_mean": -0.232, "oos_
  Tennis/MATCH_ODDS: 40048 runner-rows, 20024 books, cells 18, 83s
cells reported 18 | runner-rows 40048 | multi-line types left out (loader has no handicap value): []
NEXT DOOR (pre-registered): loader captures the runner handicap `hc` so AH/goal-line/handicap books settle (H1d); in-play bands for every sport (H1b extended).
```
### Horse Racing
```
RESULT {"name": "H1 Horse Racing WIN p0.20-0.25 BACK at close (IS rate 0.240 vs implied 0.223)", "n": 6926, "mean_per10": -0.047, "t": -0.22, "is_mean": 0.302, "is_t": 0.97, "oos_mean": -0.395, "oos_t
RESULT {"name": "H1 Horse Racing WIN p0.25-0.30 LAY at close (IS rate 0.265 vs implied 0.273)", "n": 4333, "mean_per10": -0.157, "t": -0.63, "is_mean": 0.069, "is_t": 0.2, "oos_mean": -0.388, "oos_t":
RESULT {"name": "H1 Horse Racing WIN p0.30-0.35 LAY at close (IS rate 0.313 vs implied 0.324)", "n": 2748, "mean_per10": -0.204, "t": -0.74, "is_mean": 0.124, "is_t": 0.33, "oos_mean": -0.563, "oos_t"
RESULT {"name": "H1 Horse Racing WIN p0.35-0.40 BACK at close (IS rate 0.378 vs implied 0.373)", "n": 1800, "mean_per10": -0.478, "t": -1.61, "is_mean": -0.145, "is_t": -0.34, "oos_mean": -0.811, "oos
RESULT {"name": "H1 Horse Racing WIN p0.40-0.45 BACK at close (IS rate 0.424 vs implied 0.423)", "n": 1192, "mean_per10": -0.066, "t": -0.2, "is_mean": -0.204, "is_t": -0.43, "oos_mean": 0.067, "oos_t
RESULT {"name": "H1 Horse Racing WIN p0.45-0.50 LAY at close (IS rate 0.467 vs implied 0.475)", "n": 900, "mean_per10": 0.309, "t": 0.89, "is_mean": 0.009, "is_t": 0.02, "oos_mean": 0.623, "oos_t": 1.
RESULT {"name": "H1 Horse Racing WIN p0.50-0.55 LAY at close (IS rate 0.497 vs implied 0.523)", "n": 688, "mean_per10": 0.379, "t": 1.05, "is_mean": 0.394, "is_t": 0.78, "oos_mean": 0.364, "oos_t": 0.
RESULT {"name": "H1 Horse Racing WIN p0.55-0.60 BACK at close (IS rate 0.633 vs implied 0.572)", "n": 443, "mean_per10": -0.25, "t": -0.62, "is_mean": 0.847, "is_t": 1.5, "oos_mean": -1.284, "oos_t": 
RESULT {"name": "H1 Horse Racing WIN p0.60-0.65 LAY at close (IS rate 0.594 vs implied 0.624)", "n": 319, "mean_per10": 0.155, "t": 0.36, "is_mean": 0.348, "is_t": 0.53, "oos_mean": -0.001, "oos_t": -
  Horse Racing/WIN: 124897 runner-rows, 13637 books, cells 14, 172s
cells reported 14 | runner-rows 124897 | multi-line types left out (loader has no handicap value): []
NEXT DOOR (pre-registered): loader captures the runner handicap `hc` so AH/goal-line/handicap books settle (H1d); in-play bands for every sport (H1b extended).
```
### Greyhound Racing
```
RESULT {"name": "H1 Greyhound Racing WIN p0.15-0.20 BACK at close (IS rate 0.179 vs implied 0.174)", "n": 14059, "mean_per10": -0.266, "t": -1.5, "is_mean": -0.193, "is_t": -0.76, "oos_mean": -0.338, 
RESULT {"name": "H1 Greyhound Racing WIN p0.20-0.25 BACK at close (IS rate 0.226 vs implied 0.223)", "n": 10652, "mean_per10": -0.42, "t": -2.42, "is_mean": -0.277, "is_t": -1.11, "oos_mean": -0.559, 
RESULT {"name": "H1 Greyhound Racing WIN p0.25-0.30 LAY at close (IS rate 0.267 vs implied 0.274)", "n": 7863, "mean_per10": -0.204, "t": -1.1, "is_mean": -0.053, "is_t": -0.2, "oos_mean": -0.351, "oo
RESULT {"name": "H1 Greyhound Racing WIN p0.30-0.35 LAY at close (IS rate 0.317 vs implied 0.322)", "n": 5194, "mean_per10": -0.189, "t": -0.93, "is_mean": -0.087, "is_t": -0.3, "oos_mean": -0.291, "o
RESULT {"name": "H1 Greyhound Racing WIN p0.35-0.40 BACK at close (IS rate 0.385 vs implied 0.373)", "n": 3113, "mean_per10": -0.079, "t": -0.35, "is_mean": 0.096, "is_t": 0.29, "oos_mean": -0.244, "o
RESULT {"name": "H1 Greyhound Racing WIN p0.40-0.45 LAY at close (IS rate 0.400 vs implied 0.423)", "n": 1936, "mean_per10": 0.055, "t": 0.21, "is_mean": 0.395, "is_t": 1.08, "oos_mean": -0.306, "oos_
RESULT {"name": "H1 Greyhound Racing WIN p0.45-0.50 BACK at close (IS rate 0.507 vs implied 0.473)", "n": 1245, "mean_per10": 0.076, "t": 0.26, "is_mean": 0.476, "is_t": 1.15, "oos_mean": -0.327, "oos
RESULT {"name": "H1 Greyhound Racing WIN p0.50-0.55 LAY at close (IS rate 0.460 vs implied 0.524)", "n": 790, "mean_per10": 0.793, "t": 2.35, "is_mean": 1.141, "is_t": 2.39, "oos_mean": 0.46, "oos_t":
RESULT {"name": "H1 Greyhound Racing WIN p0.55-0.60 LAY at close (IS rate 0.527 vs implied 0.573)", "n": 479, "mean_per10": 0.443, "t": 1.13, "is_mean": 0.75, "is_t": 1.34, "oos_mean": 0.143, "oos_t":
  Greyhound Racing/WIN: 86300 runner-rows, 15809 books, cells 13, 32s
cells reported 13 | runner-rows 86300 | multi-line types left out (loader has no handicap value): []
NEXT DOOR (pre-registered): loader captures the runner handicap `hc` so AH/goal-line/handicap books settle (H1d); in-play bands for every sport (H1b extended).
```

## Passed cells by sport now
[('Soccer', 16), ('Tennis', 3), ('Cricket', 2), ('Greyhound Racing', 1), ('Horse Racing', 1)]
