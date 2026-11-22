# Weekly engine 2026-11-22 00:48 UTC

```
   ('Soccer', 'FIRST_HALF_GOALS_25', Decimal('0.03'), Decimal('0.06'), 'LAY', 407, Decimal('-0.0143'), Decimal('-0.0081'))
   ('Soccer', 'HALF_TIME', Decimal('0.6'), Decimal('0.65'), 'BACK', 599, Decimal('0.016'), Decimal('0.0196'))
   ('Soccer', 'HALF_TIME', Decimal('0.65'), Decimal('0.7'), 'LAY', 342, Decimal('-0.0288'), Decimal('-0.0147'))
   ('Soccer', 'HALF_TIME_FULL_TIME', Decimal('0.3'), Decimal('0.35'), 'BACK', 1818, Decimal('0.0145'), Decimal('0.0085'))
   ('Soccer', 'HALF_TIME_FULL_TIME', Decimal('0.35'), Decimal('0.4'), 'BACK', 1227, Decimal('0.0203'), Decimal('0.023'))
   ('Soccer', 'HALF_TIME_FULL_TIME', Decimal('0.4'), Decimal('0.45'), 'LAY', 814, Decimal('-0.0108'), Decimal('-0.0168'))
   ('Soccer', 'HALF_TIME_FULL_TIME', Decimal('0.45'), Decimal('0.5'), 'BACK', 681, Decimal('0.0334'), Decimal('0.0138'))
   ('Soccer', 'OVER_UNDER_45', Decimal('0.9'), Decimal('1.0001'), 'LAY', 12341, Decimal('-0.0154'), Decimal('-0.0171'))
== 2026-11-22 00:00 weekly engine ==
Cricket exit 0 RESULT lines 11
Greyhound Racing exit 0 RESULT lines 13
Horse Racing exit 0 RESULT lines 14
Tennis exit 0 RESULT lines 18
Soccer exit 0 RESULT lines 266
  print(f"{datetime.datetime.utcnow():%Y-%m-%d %H:%M} passed cells: {n} (fair_factor BETWEEN 0.7 AND 1.3 enforced)"); [print("  ",r) for r in c.fetchall()]
cells dropped by the replay (negative on real books): 0
2026-11-22 00:40 passed cells: 21 (fair_factor BETWEEN 0.7 AND 1.3 enforced)
   ('Cricket', 'MATCH_ODDS', Decimal('0.45'), Decimal('0.5'), 'BACK', 372, Decimal('0.0217'), Decimal('0.0108'))
   ('Cricket', 'MATCH_ODDS', Decimal('0.5'), Decimal('0.55'), 'LAY', 410, Decimal('-0.0172'), Decimal('-0.0079'))
   ('Greyhound Racing', 'WIN', Decimal('0.5'), Decimal('0.55'), 'LAY', 387, Decimal('-0.0641'), Decimal('-0.0315'))
   ('Horse Racing', 'WIN', Decimal('0.5'), Decimal('0.55'), 'LAY', 348, Decimal('-0.0262'), Decimal('-0.0244'))
   ('Soccer', 'BOTH_TEAMS_TO_SCORE', Decimal('0.25'), Decimal('0.3'), 'BACK', 1021, Decimal('0.0131'), Decimal('0.0151'))
   ('Soccer', 'BOTH_TEAMS_TO_SCORE', Decimal('0.3'), Decimal('0.35'), 'BACK', 4677, Decimal('0.023'), Decimal('0.0052'))
   ('Soccer', 'BOTH_TEAMS_TO_SCORE', Decimal('0.65'), Decimal('0.7'), 'LAY', 4808, Decimal('-0.0219'), Decimal('-0.0052'))
   ('Soccer', 'BOTH_TEAMS_TO_SCORE', Decimal('0.7'), Decimal('0.8'), 'LAY', 1130, Decimal('-0.0121'), Decimal('-0.0183'))
   ('Soccer', 'CLEAN_SHEET', Decimal('0.15'), Decimal('0.2'), 'BACK', 602, Decimal('0.0134'), Decimal('0.0168'))
   ('Soccer', 'CLEAN_SHEET', Decimal('0.25'), Decimal('0.3'), 'BACK', 827, Decimal('0.0224'), Decimal('0.0176'))
   ('Soccer', 'CLEAN_SHEET', Decimal('0.35'), Decimal('0.4'), 'BACK', 622, Decimal('0.038'), Decimal('0.0554'))
   ('Soccer', 'CLEAN_SHEET', Decimal('0.6'), Decimal('0.65'), 'LAY', 609, Decimal('-0.0348'), Decimal('-0.0587'))
   ('Soccer', 'CLEAN_SHEET', Decimal('0.8'), Decimal('0.9'), 'LAY', 1167, Decimal('-0.0122'), Decimal('-0.006'))
   ('Soccer', 'CORRECT_SCORE', Decimal('0.3'), Decimal('0.35'), 'LAY', 355, Decimal('-0.0778'), Decimal('-0.0051'))
   ('Soccer', 'DOUBLE_CHANCE', Decimal('0.25'), Decimal('0.3'), 'LAY', 1721, Decimal('-0.0116'), Decimal('-0.0086'))
   ('Soccer', 'DOUBLE_CHANCE', Decimal('0.3'), Decimal('0.35'), 'LAY', 2385, Decimal('-0.0122'), Decimal('-0.0063'))
   ('Soccer', 'FIRST_HALF_GOALS_15', Decimal('0.4'), Decimal('0.45'), 'LAY', 9489, Decimal('-0.0116'), Decimal('-0.0071'))
   ('Soccer', 'FIRST_HALF_GOALS_15', Decimal('0.55'), Decimal('0.6'), 'BACK', 9444, Decimal('0.0117'), Decimal('0.0073'))
   ('Soccer', 'HALF_TIME', Decimal('0.6'), Decimal('0.65'), 'BACK', 1003, Decimal('0.012'), Decimal('0.0219'))
   ('Soccer', 'OVER_UNDER_35', Decimal('0.25'), Decimal('0.3'), 'LAY', 15518, Decimal('-0.01'), Decimal('-0.0075'))
   ('Soccer', 'OVER_UNDER_45', Decimal('0.9'), Decimal('1.0001'), 'LAY', 18179, Decimal('-0.0126'), Decimal('-0.0168'))
verifier done 00:40
```

## last 6 lines of each sport log
### fairprice_weekly_Cricket.log
```
RESULT {"name": "H1 Cricket MATCH_ODDS p0.70-0.80 BACK at close (IS rate 0.782 vs implied 0.744)", "n": 504, "mean_per10": 0.367, "t": 1.51, "is_mean": 0.306, "is_t": 0.94, "oos_mean": 0.446, "oos_t":
RESULT {"name": "H1 Cricket MATCH_ODDS p0.80-0.90 BACK at close (IS rate 0.887 vs implied 0.846)", "n": 334, "mean_per10": 0.515, "t": 2.77, "is_mean": 0.298, "is_t": 1.12, "oos_mean": 0.82, "oos_t": 
RESULT {"name": "H1 Cricket MATCH_ODDS p0.90-1.00 BACK at close (IS rate 0.975 vs implied 0.947)", "n": 325, "mean_per10": 0.119, "t": 1.18, "is_mean": 0.195, "is_t": 1.48, "oos_mean": 0.046, "oos_t":
  Cricket/MATCH_ODDS: 8313 runner-rows, 4123 books, cells 11, 15s
cells reported 11 | runner-rows 8313 | multi-line types left out (loader has no handicap value): []
NEXT DOOR (pre-registered): loader captures the runner handicap `hc` so AH/goal-line/handicap books settle (H1d); in-play bands for every sport (H1b extended).
```
### fairprice_weekly_Greyhound_Racing.log
```
RESULT {"name": "H1 Greyhound Racing WIN p0.45-0.50 BACK at close (IS rate 0.507 vs implied 0.473)", "n": 1245, "mean_per10": 0.076, "t": 0.26, "is_mean": 0.476, "is_t": 1.15, "oos_mean": -0.327, "oos
RESULT {"name": "H1 Greyhound Racing WIN p0.50-0.55 LAY at close (IS rate 0.460 vs implied 0.524)", "n": 790, "mean_per10": 0.793, "t": 2.35, "is_mean": 1.141, "is_t": 2.39, "oos_mean": 0.46, "oos_t":
RESULT {"name": "H1 Greyhound Racing WIN p0.55-0.60 LAY at close (IS rate 0.527 vs implied 0.573)", "n": 479, "mean_per10": 0.443, "t": 1.13, "is_mean": 0.75, "is_t": 1.34, "oos_mean": 0.143, "oos_t":
  Greyhound Racing/WIN: 86300 runner-rows, 15809 books, cells 13, 20s
cells reported 13 | runner-rows 86300 | multi-line types left out (loader has no handicap value): []
NEXT DOOR (pre-registered): loader captures the runner handicap `hc` so AH/goal-line/handicap books settle (H1d); in-play bands for every sport (H1b extended).
```
### fairprice_weekly_Horse_Racing.log
```
RESULT {"name": "H1 Horse Racing WIN p0.50-0.55 LAY at close (IS rate 0.497 vs implied 0.523)", "n": 688, "mean_per10": 0.379, "t": 1.05, "is_mean": 0.394, "is_t": 0.78, "oos_mean": 0.364, "oos_t": 0.
RESULT {"name": "H1 Horse Racing WIN p0.55-0.60 BACK at close (IS rate 0.633 vs implied 0.572)", "n": 443, "mean_per10": -0.25, "t": -0.62, "is_mean": 0.847, "is_t": 1.5, "oos_mean": -1.284, "oos_t": 
RESULT {"name": "H1 Horse Racing WIN p0.60-0.65 LAY at close (IS rate 0.594 vs implied 0.624)", "n": 319, "mean_per10": 0.155, "t": 0.36, "is_mean": 0.348, "is_t": 0.53, "oos_mean": -0.001, "oos_t": -
  Horse Racing/WIN: 124897 runner-rows, 13637 books, cells 14, 104s
cells reported 14 | runner-rows 124897 | multi-line types left out (loader has no handicap value): []
NEXT DOOR (pre-registered): loader captures the runner handicap `hc` so AH/goal-line/handicap books settle (H1d); in-play bands for every sport (H1b extended).
```
### fairprice_weekly_Soccer.log
```
RESULT {"name": "H1 Soccer TEAM_B_OVER_UNDER_15 p0.65-0.70 BACK at close (IS rate 0.702 vs implied 0.674)", "n": 347, "mean_per10": 0.25, "t": 0.7, "is_mean": 0.197, "is_t": 0.38, "oos_mean": 0.301, "
RESULT {"name": "H1 Soccer TEAM_B_OVER_UNDER_15 p0.70-0.80 LAY at close (IS rate 0.737 vs implied 0.748)", "n": 539, "mean_per10": 0.15, "t": 0.6, "is_mean": 0.177, "is_t": 0.5, "oos_mean": 0.125, "oo
  Soccer/TEAM_B_OVER_UNDER_15: 4398 runner-rows, 2199 books, cells 9, 2162s
  Soccer/WINNING_MARGIN: 20 runner-rows on complete books — skipped
cells reported 266 | runner-rows 5843278 | multi-line types left out (loader has no handicap value): ['Soccer/ASIAN_HANDICAP']
NEXT DOOR (pre-registered): loader captures the runner handicap `hc` so AH/goal-line/handicap books settle (H1d); in-play bands for every sport (H1b extended).
```
### fairprice_weekly_Tennis.log
```
RESULT {"name": "H1 Tennis MATCH_ODDS p0.70-0.80 LAY at close (IS rate 0.737 vs implied 0.746)", "n": 9651, "mean_per10": -0.063, "t": -1.07, "is_mean": 0.047, "is_t": 0.57, "oos_mean": -0.175, "oos_t
RESULT {"name": "H1 Tennis MATCH_ODDS p0.80-0.90 LAY at close (IS rate 0.835 vs implied 0.842)", "n": 5705, "mean_per10": -0.086, "t": -1.53, "is_mean": 0.02, "is_t": 0.24, "oos_mean": -0.188, "oos_t"
RESULT {"name": "H1 Tennis MATCH_ODDS p0.90-1.00 BACK at close (IS rate 0.959 vs implied 0.938)", "n": 3112, "mean_per10": -0.001, "t": -0.04, "is_mean": 0.093, "is_t": 1.66, "oos_mean": -0.079, "oos_
  Tennis/MATCH_ODDS: 95062 runner-rows, 47531 books, cells 18, 38s
cells reported 18 | runner-rows 95062 | multi-line types left out (loader has no handicap value): []
NEXT DOOR (pre-registered): loader captures the runner handicap `hc` so AH/goal-line/handicap books settle (H1d); in-play bands for every sport (H1b extended).
```
