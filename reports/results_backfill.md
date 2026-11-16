# Results backfill and engine, every sport — 2026-11-16 04:24 UTC

## Backfill
- Tennis: markets re-read 55265, result rows 87192 -> 208384, result markets 104191, of which 52058 join to a price market

## Engine
```
   ('Soccer', 'HALF_TIME_FULL_TIME', Decimal('0.4'), Decimal('0.45'), 'LAY', 814, Decimal('-0.0108'), Decimal('-0.0168'))
   ('Soccer', 'HALF_TIME_FULL_TIME', Decimal('0.45'), Decimal('0.5'), 'BACK', 681, Decimal('0.0334'), Decimal('0.0138'))
   ('Soccer', 'OVER_UNDER_45', Decimal('0.9'), Decimal('1.0001'), 'LAY', 12341, Decimal('-0.0154'), Decimal('-0.0171'))
   ('Tennis', 'MATCH_ODDS', Decimal('0.2'), Decimal('0.25'), 'LAY', 909, Decimal('-0.0149'), Decimal('-0.0292'))
   ('Tennis', 'MATCH_ODDS', Decimal('0.4'), Decimal('0.45'), 'LAY', 1678, Decimal('-0.0116'), Decimal('-0.006'))
   ('Tennis', 'MATCH_ODDS', Decimal('0.55'), Decimal('0.6'), 'BACK', 1676, Decimal('0.0111'), Decimal('0.0057'))
  print(f"{datetime.datetime.utcnow():%Y-%m-%d %H:%M} passed cells: {n} (fair_factor BETWEEN 0.7 AND 1.3 enforced)"); [print("  ",r) for r in c.fetchall()]
cells dropped by the replay (negative on real books): 0
2026-11-16 04:24 passed cells: 20 (fair_factor BETWEEN 0.7 AND 1.3 enforced)
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

```
### Tennis
```
RESULT {"name": "H1 Tennis MATCH_ODDS p0.40-0.45 BACK at close (IS rate 0.427 vs implied 0.425)", "n": 7880, "mean_per10": -0.283, "t": -2.22, "is_mean": -0.22, "is_t": -1.23, "oos_mean": -0.35, "oos_
RESULT {"name": "H1 Tennis MATCH_ODDS p0.45-0.50 BACK at close (IS rate 0.479 vs implied 0.474)", "n": 6872, "mean_per10": -0.205, "t": -1.66, "is_mean": -0.144, "is_t": -0.83, "oos_mean": -0.269, "oo
RESULT {"name": "H1 Tennis MATCH_ODDS p0.50-0.55 LAY at close (IS rate 0.519 vs implied 0.524)", "n": 7296, "mean_per10": -0.057, "t": -0.52, "is_mean": 0.002, "is_t": 0.01, "oos_mean": -0.119, "oos_t
RESULT {"name": "H1 Tennis MATCH_ODDS p0.55-0.60 LAY at close (IS rate 0.573 vs implied 0.575)", "n": 7865, "mean_per10": -0.097, "t": -1.01, "is_mean": -0.026, "is_t": -0.19, "oos_mean": -0.172, "oos
RESULT {"name": "H1 Tennis MATCH_ODDS p0.60-0.65 LAY at close (IS rate 0.606 vs implied 0.624)", "n": 7562, "mean_per10": 0.012, "t": 0.13, "is_mean": 0.21, "is_t": 1.69, "oos_mean": -0.198, "oos_t": 
RESULT {"name": "H1 Tennis MATCH_ODDS p0.65-0.70 BACK at close (IS rate 0.684 vs implied 0.674)", "n": 6552, "mean_per10": 0.034, "t": 0.41, "is_mean": -0.042, "is_t": -0.35, "oos_mean": 0.105, "oos_t
RESULT {"name": "H1 Tennis MATCH_ODDS p0.70-0.80 LAY at close (IS rate 0.737 vs implied 0.746)", "n": 9651, "mean_per10": -0.063, "t": -1.07, "is_mean": 0.047, "is_t": 0.57, "oos_mean": -0.175, "oos_t
RESULT {"name": "H1 Tennis MATCH_ODDS p0.80-0.90 LAY at close (IS rate 0.835 vs implied 0.842)", "n": 5705, "mean_per10": -0.086, "t": -1.53, "is_mean": 0.02, "is_t": 0.24, "oos_mean": -0.188, "oos_t"
RESULT {"name": "H1 Tennis MATCH_ODDS p0.90-1.00 BACK at close (IS rate 0.959 vs implied 0.938)", "n": 3112, "mean_per10": -0.001, "t": -0.04, "is_mean": 0.093, "is_t": 1.66, "oos_mean": -0.079, "oos_
  Tennis/MATCH_ODDS: 95062 runner-rows, 47531 books, cells 18, 46s
cells reported 18 | runner-rows 95062 | multi-line types left out (loader has no handicap value): []
NEXT DOOR (pre-registered): loader captures the runner handicap `hc` so AH/goal-line/handicap books settle (H1d); in-play bands for every sport (H1b extended).
```

## Passed cells by sport now
[('Soccer', 16), ('Cricket', 2), ('Greyhound Racing', 1), ('Horse Racing', 1)]
