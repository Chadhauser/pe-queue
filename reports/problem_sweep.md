<stdin>:7: DeprecationWarning: datetime.datetime.utcnow() is deprecated and scheduled for removal in a future version. Use timezone-aware objects to represent datetimes in UTC: datetime.datetime.now(datetime.UTC).
# Problem sweep — paper bot and recorders — 2026-11-16 17:08 UTC

## Bot settings in code

- STAKE=2.0; COMM=0.02; TTL=600; REQUOTE=300; MIN_MATCHED=2000.0; MIN_SIZE=10.0; MAX_PRICE=20.0; MAX_SPREAD=3; HORIZON_MIN=60; VERSION='v2'; MODE='taker'; TAKE_WINDOW_S=120   # 549: take, don't make

## Paper bets per day (last 10 days)
| day | placed | filled | settled | pnl £ | avg fill vs asked |
|---|---|---|---|---|---|
|2026-11-06|24064|6591|6591|-31039.83|0.0000|
|2026-11-07|23894|6650|6650|-10920.04|0.0000|
|2026-11-08|10486|780|780|-48.32|0.0000|
|2026-11-09|1729|330|330|1.62|0.0000|
|2026-11-10|2761|76|28|4.09|0.0000|
|2026-11-11|5|5|5|10.62|0.0000|
|2026-11-12|14|14|14|-9.86|0.0000|
|2026-11-14|12|12|12|-8.50|0.0000|
|2026-11-15|14|14|14|-4.62|0.0000|
|2026-11-16|22|22|14|8.28|0.0000|

## Status / fill kind last 7 days

[('expired', None, 3510, Decimal('0.00')), ('unsettleable', 'maker', 247, Decimal('0.00')), ('settled', 'taker', 65, Decimal('0.02')), ('open', None, 64, Decimal('0.00')), ('filled', 'maker', 48, Decimal('0.00')), ('settled', 'maker', 32, Decimal('1.62')), ('filled', 'taker', 8, Decimal('0.00'))]

## Settled bets by market type since 11 Nov

[('OVER_UNDER_45', 'LAY', 10, Decimal('2.38'), Decimal('11.9')), ('WIN', 'LAY', 10, Decimal('8.16'), Decimal('40.8')), ('OVER_UNDER_25', 'BACK', 7, Decimal('3.78'), Decimal('27.0')), ('OVER_UNDER_25', 'LAY', 6, Decimal('5.30'), Decimal('44.2')), ('BOTH_TEAMS_TO_SCORE', 'LAY', 4, Decimal('1.86'), Decimal('23.3')), ('FIRST_HALF_GOALS_15', 'BACK', 4, Decimal('-8.00'), Decimal('-100.0')), ('FIRST_HALF_GOALS_15', 'LAY', 3, Decimal('-1.88'), Decimal('-31.3')), ('FIRST_GOAL_SCORER', 'LAY', 3, Decimal('-7.68'), Decimal('-128.0')), ('BOTH_TEAMS_TO_SCORE', 'BACK', 2, Decimal('-4.00'), Decimal('-100.0')), ('CORRECT_SCORE', 'BACK', 2, Decimal('3.88'), Decimal('97.0')), ('FIRST_HALF_GOALS_25', 'BACK', 2, Decimal('-4.00'), Decimal('-100.0')), ('MATCH_ODDS', 'LAY', 2, Decimal('0.16'), Decimal('4.0')), ('MATCH_ODDS', 'BACK', 1, Decimal('-2.00'), Decimal('-100.0')), ('HALF_TIME_FULL_TIME', 'BACK', 1, Decimal('-2.00'), Decimal('-100.0')), ('HALF_TIME', 'LAY', 1, Decimal('1.96'), Decimal('98.0')), ('DRAW_NO_BET', 'BACK', 1, Decimal('-2.00'), Decimal('-100.0'))]

## Bets per event (correlation) last 7 days, filled

[(42, Decimal('4.60'), 38)]

## Pace to the 100-bet gate

Settled since 11 Nov: 59. Settling per day (last 5 days): 11.8.

## Heartbeat and recorders

bookie_heartbeat latest: [(9, datetime.datetime(2026, 11, 16, 10, 5, 58, 668781, tzinfo=datetime.timezone.utc), 0, 0)]
stream_ticks rows per hour, last 8 h: [(datetime.datetime(2026, 11, 16, 9, 0, tzinfo=datetime.timezone.utc), 41346), (datetime.datetime(2026, 11, 16, 10, 0, tzinfo=datetime.timezone.utc), 56733), (datetime.datetime(2026, 11, 16, 11, 0, tzinfo=datetime.timezone.utc), 115614), (datetime.datetime(2026, 11, 16, 12, 0, tzinfo=datetime.timezone.utc), 186884), (datetime.datetime(2026, 11, 16, 13, 0, tzinfo=datetime.timezone.utc), 295233), (datetime.datetime(2026, 11, 16, 14, 0, tzinfo=datetime.timezone.utc), 383480), (datetime.datetime(2026, 11, 16, 15, 0, tzinfo=datetime.timezone.utc), 443457), (datetime.datetime(2026, 11, 16, 16, 0, tzinfo=datetime.timezone.utc), 601390), (datetime.datetime(2026, 11, 16, 17, 0, tzinfo=datetime.timezone.utc), 74991)]
liq_sample rows per hour, last 8 h: [(datetime.datetime(2026, 11, 16, 9, 0, tzinfo=datetime.timezone.utc), 34871), (datetime.datetime(2026, 11, 16, 10, 0, tzinfo=datetime.timezone.utc), 42126), (datetime.datetime(2026, 11, 16, 11, 0, tzinfo=datetime.timezone.utc), 81721), (datetime.datetime(2026, 11, 16, 12, 0, tzinfo=datetime.timezone.utc), 90170), (datetime.datetime(2026, 11, 16, 13, 0, tzinfo=datetime.timezone.utc), 120673), (datetime.datetime(2026, 11, 16, 14, 0, tzinfo=datetime.timezone.utc), 122027), (datetime.datetime(2026, 11, 16, 15, 0, tzinfo=datetime.timezone.utc), 160268), (datetime.datetime(2026, 11, 16, 16, 0, tzinfo=datetime.timezone.utc), 163721), (datetime.datetime(2026, 11, 16, 17, 0, tzinfo=datetime.timezone.utc), 23089)]

## Passed cells in force

[]
['sport', 'market_type', 'band_lo', 'band_hi', 'side', 'fair_factor', 'n_is', 'n_oos', 'edge_is', 'edge_oos', 'source', 'passed_at']
[(20,)]
