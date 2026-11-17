# In-play fair-price engine + verifier — started 2026-11-17 07:12 UTC (job 639)

```
Soccer exit 0 RESULT lines 1074
cells reported 1074 | runner-rows 11021132 | markets dropped (no single official winner) 0
NEXT DOOR (pre-registered): H1c by country/league tier; H1d multi-line markets (AH, goal line) with line-aware settlement.
Tennis exit 0 RESULT lines 1074
cells reported 1074 | runner-rows 11021132 | markets dropped (no single official winner) 0
NEXT DOOR (pre-registered): H1c by country/league tier; H1d multi-line markets (AH, goal line) with line-aware settlement.
Cricket exit 0 RESULT lines 1074
cells reported 1074 | runner-rows 11021135 | markets dropped (no single official winner) 0
NEXT DOOR (pre-registered): H1c by country/league tier; H1d multi-line markets (AH, goal line) with line-aware settlement.
Horse Racing exit 0 RESULT lines 1074
cells reported 1074 | runner-rows 11021445 | markets dropped (no single official winner) 0
NEXT DOOR (pre-registered): H1c by country/league tier; H1d multi-line markets (AH, goal line) with line-aware settlement.
Greyhound Racing exit 0 RESULT lines 1074
cells reported 1074 | runner-rows 11021599 | markets dropped (no single official winner) 0
NEXT DOOR (pre-registered): H1c by country/league tier; H1d multi-line markets (AH, goal line) with line-aware settlement.
```

## Verifier
```
  print(f"{datetime.datetime.utcnow():%Y-%m-%d %H:%M} passed cells: {n} (fair_factor BETWEEN 0.7 AND 1.3 enforced)"); [print("  ",r) for r in c.fetchall()]
cells dropped by the replay (negative on real books): 0
2026-11-17 08:44 passed cells: 20 (fair_factor BETWEEN 0.7 AND 1.3 enforced)
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
finished 2026-11-17 08:44 UTC
