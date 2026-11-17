# 644 — 2026-11-17 14:02 UTC
```
small bites (cell, liq, trades, closed, stuck, open, pnl, gross wins):
   ('DRIFT_FADE k3 H10', '50k-500k', 5, 5, 0, 0, Decimal('-0.46'), Decimal('0.00'))
   ('DRIFT_FADE k5 H10', '50k-500k', 4, 4, 0, 0, Decimal('-0.42'), Decimal('0.00'))
   ('DRIFT_FADE k5 H10', '5k-50k', 35, 27, 1, 7, Decimal('0.41'), Decimal('14.28'))
   ('DRIFT_FADE k5 H10', '<5k', 58, 48, 3, 7, Decimal('6.41'), Decimal('27.76'))
   ('STEAM_FOLLOW k2 H10', '5k-50k', 4, 2, 1, 1, Decimal('-2.53'), Decimal('0.55'))
   ('STEAM_FOLLOW k2 H10', '<5k', 52, 37, 4, 11, Decimal('-7.07'), Decimal('8.54'))
   ('STEAM_FOLLOW k2 H5', '<5k', 13, 13, 0, 0, Decimal('-0.59'), Decimal('2.05'))
   ('STEAM_FOLLOW k3 H10', '5k-50k', 4, 2, 0, 2, Decimal('-0.53'), Decimal('0.55'))
   ('STEAM_FOLLOW k3 H10', '<5k', 53, 40, 3, 10, Decimal('-4.54'), Decimal('9.15'))
   ('STEAM_FOLLOW k3 H5', '<5k', 11, 11, 0, 0, Decimal('-1.23'), Decimal('1.41'))
   ('STEAM_FOLLOW k5 H10', '5k-50k', 6, 3, 0, 3, Decimal('-0.68'), Decimal('0.87'))
   ('STEAM_FOLLOW k5 H10', '<5k', 51, 45, 0, 6, Decimal('1.47'), Decimal('8.94'))
small bites total: (296, Decimal('-9.76'), datetime.datetime(2026, 11, 17, 10, 11, 2, 365074, tzinfo=datetime.timezone.utc), datetime.datetime(2026, 11, 17, 14, 2, 2, 698510, tzinfo=datetime.timezone.utc))
bot last 24h: [('v2', 'settled', 18, Decimal('-4.70')), ('v2.2', 'settled', 1, Decimal('-0.18'))]
bot settled this month by version: [('v0', 33924, Decimal('-31031.20')), ('v1', 12149, Decimal('-48702.75')), ('v1.1', 1924, Decimal('-365.20')), ('v2', 89, Decimal('-2.91')), ('v2.2', 1, Decimal('-0.18')), (None, 95, Decimal('-116.29'))]
--- /root/pe-stream/stream.log around the gap
16329:stream error JSONDecodeError('Expecting value: line 1 column 1 (char 0)') -> retry in 60
16330:stream error JSONDecodeError('Expecting value: line 1 column 1 (char 0)') -> retry in 60
16331:stream error JSONDecodeError('Expecting value: line 1 column 1 (char 0)') -> retry in 60
16333:auth: {"op":"status","id":1,"statusCode":"SUCCESS","connectionClosed":false,"connectionsAvailable":9}
16336:STATUS FAILURE {'op': 'status', 'statusCode': 'FAILURE', 'errorCode': 'TIMEOUT', 'errorMessage': 'Connection is not subscribed and is idle: 15000 ms', 'connectionClosed': True, 'connectionId': '210-171126090835-262
16337:stream error ConnectionError("{'op': 'status', 'statusCode': 'FAILURE', 'errorCode': 'TIMEOUT', 'errorMessage': 'Connection is not subscribed and is idle: 15000 ms', 'connec -> retry in 2
16339:auth: {"op":"status","id":1,"statusCode":"SUCCESS","connectionClosed":false,"connectionsAvailable":9}
16343:auth: {"op":"status","id":1,"statusCode":"SUCCESS","connectionClosed":false,"connectionsAvailable":9}
16346:STATUS FAILURE {'op': 'status', 'statusCode': 'FAILURE', 'errorCode': 'TIMEOUT', 'errorMessage': 'Connection is not subscribed and is idle: 15000 ms', 'connectionClosed': True, 'connectionId': '204-171126092101-452
16347:stream error ConnectionError("{'op': 'status', 'statusCode': 'FAILURE', 'errorCode': 'TIMEOUT', 'errorMessage': 'Connection is not subscribed and is idle: 15000 ms', 'connec -> retry in 2
16349:auth: {"op":"status","id":1,"statusCode":"SUCCESS","connectionClosed":false,"connectionsAvailable":9}
16354:auth: {"op":"status","id":1,"statusCode":"SUCCESS","connectionClosed":false,"connectionsAvailable":9}
16357:STATUS FAILURE {'op': 'status', 'statusCode': 'FAILURE', 'errorCode': 'TIMEOUT', 'errorMessage': 'Connection is not subscribed and is idle: 15000 ms', 'connectionClosed': True, 'connectionId': '105-171126094102-606
16358:stream error ConnectionError("{'op': 'status', 'statusCode': 'FAILURE', 'errorCode': 'TIMEOUT', 'errorMessage': 'Connection is not subscribed and is idle: 15000 ms', 'connec -> retry in 2
16360:auth: {"op":"status","id":1,"statusCode":"SUCCESS","connectionClosed":false,"connectionsAvailable":9}
```
