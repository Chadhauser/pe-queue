# Apply 626 — 2026-11-17 06:38 UTC

## A. Bot value filter + prune
bot patched (4/4)
compiles
7:STAKE=2.0; COMM=0.02; TTL=600; REQUOTE=300; MIN_MATCHED=2000.0; MIN_SIZE=10.0; MAX_PRICE=20.0; MAX_SPREAD=3; HORIZON_MIN=60; VERSION='v2.1'; MODE='taker'; TAKE_WINDOW_S=120; VALUE_M=0.01   # 626: take only 1%+ better than fair   # 549: take, don't make
117:                    if side=='BACK' and bb>=fair*(1+VALUE_M): q=('BACK',bb)
118:                    elif side=='LAY' and bl<=fair*(1-VALUE_M): q=('LAY',bl)
pruned 6 cells (copied 6 first)
  kept: Cricket MATCH_ODDS 0.45 0.5 BACK
  kept: Cricket MATCH_ODDS 0.5 0.55 LAY
  kept: Greyhound Racing WIN 0.5 0.55 LAY
  kept: Horse Racing WIN 0.5 0.55 LAY
  kept: Soccer BOTH_TEAMS_TO_SCORE 0.3 0.35 BACK
  kept: Soccer BOTH_TEAMS_TO_SCORE 0.65 0.7 LAY
  kept: Soccer CLEAN_SHEET 0.7 0.8 LAY
  kept: Soccer FIRST_GOAL_SCORER 0.1 0.15 LAY
  kept: Soccer FIRST_HALF_GOALS_05 0.4 0.45 BACK
  kept: Soccer FIRST_HALF_GOALS_05 0.55 0.6 LAY
  kept: Soccer FIRST_HALF_GOALS_25 0.03 0.06 LAY
  kept: Soccer HALF_TIME 0.6 0.65 BACK
  kept: Soccer HALF_TIME 0.65 0.7 LAY
  kept: Soccer OVER_UNDER_45 0.9 1.0001 LAY
#!/bin/bash
cd /root/pe-sports/bookie && while true; do python3 bookie_v2.py >> bookie_v2.out 2>&1; sleep 15; done
bot processes: 1

## B. Small bites forward paper
compiles
processes: 1
```
2026-11-17 06:38 selections 12 new 0 open 0 today 0
2026-11-17 06:39 selections 12 new 0 open 0 today 0
2026-11-17 06:40 selections 12 new 0 open 0 today 0
2026-11-17 06:41 selections 12 new 0 open 0 today 0
2026-11-17 06:42 selections 12 new 0 open 0 today 0
```
paper rows: []
heartbeat: [(1, datetime.datetime(2026, 11, 17, 6, 42, 2, 638386, tzinfo=datetime.timezone.utc), 0, 0, 'selections 12 new 0')]

## C. Bot markets on the tape
bot markets since 11 Nov: 61 sample: [('1.265567324', '1.265567324', 'OVER_UNDER_45'), ('1.265400819', '1.265400819', 'BOTH_TEAMS_TO_SCORE'), ('1.265544325', '1.265544325', 'BOTH_TEAMS_TO_SCORE')]
of those on stream_ticks: 34
stream market_id format: [('1.265533635',), ('1.265533635',), ('1.265549535',)]
stream markets by type, 6h: [('MO', 36), ('OU25', 5), ('DOUBLE_CHANCE', 4), ('FIRST_HALF_GOALS_05', 4), ('FIRST_HALF_GOALS_25', 4), ('HALF_TIME', 4), ('HALF_TIME_FULL_TIME', 4), ('MO_PRE', 4), ('BOTH_TEAMS_TO_SCORE', 4), ('OVER_UNDER_45', 4), ('CORRECT_SCORE', 4)]
bot bets by type: [('WIN', 18), ('OVER_UNDER_25', 13), ('OVER_UNDER_45', 12), ('BOTH_TEAMS_TO_SCORE', 8), ('FIRST_HALF_GOALS_15', 7), ('MATCH_ODDS', 6), ('CORRECT_SCORE', 4), ('FIRST_GOAL_SCORER', 3), ('FIRST_HALF_GOALS_25', 2), ('HALF_TIME_FULL_TIME', 2), ('DRAW_NO_BET', 1), ('HALF_TIME', 1)]
