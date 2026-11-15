# Weekly engine 2026-11-15 15:52 UTC

```
   ('Soccer', 'CORRECT_SCORE', Decimal('0.2'), Decimal('0.25'), 'BACK', 482, Decimal('0.0286'), Decimal('0.0347'))
   ('Soccer', 'DRAW_NO_BET', Decimal('0.06'), Decimal('0.1'), 'LAY', 486, Decimal('-0.0192'), Decimal('-0.0152'))
   ('Soccer', 'DRAW_NO_BET', Decimal('0.2'), Decimal('0.25'), 'BACK', 1353, Decimal('0.0108'), Decimal('0.0103'))
   ('Soccer', 'DRAW_NO_BET', Decimal('0.9'), Decimal('1.0001'), 'BACK', 852, Decimal('0.0156'), Decimal('0.0146'))
   ('Soccer', 'FIRST_HALF_GOALS_05', Decimal('0.4'), Decimal('0.45'), 'BACK', 915, Decimal('0.0279'), Decimal('0.0338'))
   ('Soccer', 'FIRST_HALF_GOALS_05', Decimal('0.55'), Decimal('0.6'), 'LAY', 896, Decimal('-0.0269'), Decimal('-0.0348'))
   ('Soccer', 'FIRST_HALF_GOALS_15', Decimal('0.45'), Decimal('0.5'), 'BACK', 3225, Decimal('0.0115'), Decimal('0.0084'))
   ('Soccer', 'FIRST_HALF_GOALS_15', Decimal('0.5'), Decimal('0.55'), 'LAY', 3431, Decimal('-0.0108'), Decimal('-0.008'))
   ('Soccer', 'FIRST_HALF_GOALS_25', Decimal('0.2'), Decimal('0.25'), 'BACK', 2125, Decimal('0.0114'), Decimal('0.0099'))
   ('Soccer', 'HALF_TIME', Decimal('0.6'), Decimal('0.65'), 'BACK', 438, Decimal('0.0206'), Decimal('0.0273'))
   ('Soccer', 'HALF_TIME_FULL_TIME', Decimal('0.3'), Decimal('0.35'), 'BACK', 1237, Decimal('0.0121'), Decimal('0.0145'))
   ('Soccer', 'HALF_TIME_FULL_TIME', Decimal('0.35'), Decimal('0.4'), 'BACK', 824, Decimal('0.0263'), Decimal('0.0162'))
   ('Soccer', 'HALF_TIME_FULL_TIME', Decimal('0.45'), Decimal('0.5'), 'BACK', 453, Decimal('0.0293'), Decimal('0.0075'))
   ('Soccer', 'OVER_UNDER_25', Decimal('0.3'), Decimal('0.35'), 'LAY', 3936, Decimal('-0.0122'), Decimal('-0.011'))
   ('Soccer', 'OVER_UNDER_25', Decimal('0.65'), Decimal('0.7'), 'BACK', 4026, Decimal('0.0121'), Decimal('0.0097'))
   ('Soccer', 'OVER_UNDER_45', Decimal('0.9'), Decimal('1.0001'), 'LAY', 8241, Decimal('-0.0159'), Decimal('-0.019'))
verifier done 00:27
== 2026-11-15 15:24 weekly engine ==
Soccer exit 0 RESULT lines 232
  print(f"{datetime.datetime.utcnow():%Y-%m-%d %H:%M} passed cells: {n} (fair_factor BETWEEN 0.7 AND 1.3 enforced)"); [print("  ",r) for r in c.fetchall()]
cells dropped by the replay (negative on real books): 0
2026-11-15 15:52 passed cells: 16 (fair_factor BETWEEN 0.7 AND 1.3 enforced)
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
verifier done 15:52
```

## last 6 lines of each sport log
### fairprice_weekly_Cricket.log
```
    cur.execute("SELECT sport, market_type, count(DISTINCT market_id) FROM bf_hist_other GROUP BY 1,2 HAVING count(DISTINCT market_id)>=200 ORDER BY 1, 3 DESC"); types=cur.fetchall()
    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
psycopg2.OperationalError: server closed the connection unexpectedly
	This probably means the server terminated abnormally
	before or while processing the request.

```
### fairprice_weekly_Greyhound_Racing.log
```
    cur.execute("SELECT sport, market_type, count(DISTINCT market_id) FROM bf_hist_other GROUP BY 1,2 HAVING count(DISTINCT market_id)>=200 ORDER BY 1, 3 DESC"); types=cur.fetchall()
    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
psycopg2.OperationalError: server closed the connection unexpectedly
	This probably means the server terminated abnormally
	before or while processing the request.

```
### fairprice_weekly_Horse_Racing.log
```
    cur.execute("SELECT sport, market_type, count(DISTINCT market_id) FROM bf_hist_other GROUP BY 1,2 HAVING count(DISTINCT market_id)>=200 ORDER BY 1, 3 DESC"); types=cur.fetchall()
    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
psycopg2.OperationalError: server closed the connection unexpectedly
	This probably means the server terminated abnormally
	before or while processing the request.

```
### fairprice_weekly_Soccer.log
```
  Soccer/TEAM_B_OVER_UNDER_05: 2293 runner-rows, 1147 books, cells 0, 1628s
  Soccer/TEAM_B_OVER_UNDER_15: dates 2021-09-11..2026-09-20, split 2023-12-23, winners/market mean 1.00
RESULT {"name": "H1 Soccer TEAM_B_OVER_UNDER_15 p0.70-0.80 BACK at close (IS rate 0.750 vs implied 0.749)", "n": 308, "mean_per10": -0.225, "t": -0.69, "is_mean": -0.223, "is_t": -0.49, "oos_mean": -0
  Soccer/TEAM_B_OVER_UNDER_15: 2360 runner-rows, 1180 books, cells 1, 1630s
cells reported 232 | runner-rows 3405648 | multi-line types left out (loader has no handicap value): ['Soccer/ASIAN_HANDICAP']
NEXT DOOR (pre-registered): loader captures the runner handicap `hc` so AH/goal-line/handicap books settle (H1d); in-play bands for every sport (H1b extended).
```
### fairprice_weekly_Tennis.log
```
    cur.execute("SELECT sport, market_type, count(DISTINCT market_id) FROM bf_hist_other GROUP BY 1,2 HAVING count(DISTINCT market_id)>=200 ORDER BY 1, 3 DESC"); types=cur.fetchall()
    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
psycopg2.OperationalError: server closed the connection unexpectedly
	This probably means the server terminated abnormally
	before or while processing the request.

```
