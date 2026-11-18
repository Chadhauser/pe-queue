# 657 — 2026-11-18 06:38 UTC
```
compiles
recorder processes: 1
Wed Nov 18 06:38:08 UTC 2026 exited 0
/root/pe-sports/team/book_recorder.py:52: DeprecationWarning: datetime.datetime.utcnow() is deprecated and scheduled for removal in a future version. Use timezone-aware objects to represent datetimes 
  cat_t = time.time(); print(f"{dt.datetime.utcnow():%F %H:%M:%S} events {len(evs)} markets {len(cat)}", flush=True)
2026-11-18 06:38:39 events 6 markets 105
book heartbeat: [(1, datetime.datetime(2026, 11, 18, 6, 40, 30, 92454, tzinfo=datetime.timezone.utc), 105, 0, 'due 0')]
last 3 min markets/events: (128, 6)

== small bites forward: what the losers share
status [('stuck', 175, Decimal('-350.00'), Decimal('-2.000')), ('closed', 1569, Decimal('149.17'), Decimal('0.095'))]
liq [('5k-50k', 566, Decimal('-111.05'), Decimal('-0.196')), ('<5k', 943, Decimal('-76.07'), Decimal('-0.081')), ('50k-500k', 235, Decimal('-13.71'), Decimal('-0.058'))]
cell [('STEAM_FOLLOW k2 H10', 301, Decimal('-57.44'), Decimal('-0.191')), ('DRIFT_FADE k5 H10', 616, Decimal('-54.99'), Decimal('-0.089')), ('STEAM_FOLLOW k3 H10', 297, Decimal('-48.33'), Decimal('-0.163')), ('STEAM_FOLLOW k5 H10', 329, Decimal('-32.44'), Decimal('-0.099')), ('DRIFT_FADE k3 H10', 126, Decimal('-6.28'), Decimal('-0.050')), ('STEAM_FOLLOW k2 H5', 43, Decimal('-1.69'), Decimal('-0.039')), ('STEAM_FOLLOW k3 H5', 32, Decimal('0.35'), Decimal('0.011'))]
CASE WHEN entry_px < 2 THEN 'a <2' WHEN  [('a <2', 652, Decimal('-168.46'), Decimal('-0.258')), ('b 2-3', 288, Decimal('-19.03'), Decimal('-0.066')), ('e 10+', 206, Decimal('-18.21'), Decimal('-0.088')), ('d 5-10', 282, Decimal('-10.19'), Decimal('-0.036')), ('c 3-5', 316, Decimal('15.06'), Decimal('0.048'))]
CASE WHEN exit_min - entry_min > interva [('exit on time', 1715, Decimal('-201.04'), Decimal('-0.117')), ('exit late (suspended)', 29, Decimal('0.21'), Decimal('0.007'))]
extract(hour from entry_min)::int [(14, 174, Decimal('-58.87'), Decimal('-0.338')), (19, 206, Decimal('-42.28'), Decimal('-0.205')), (12, 102, Decimal('-29.32'), Decimal('-0.287')), (16, 139, Decimal('-22.29'), Decimal('-0.160')), (20, 288, Decimal('-21.50'), Decimal('-0.075')), (0, 82, Decimal('-18.46'), Decimal('-0.225')), (21, 115, Decimal('-16.25'), Decimal('-0.141')), (4, 12, Decimal('-7.37'), Decimal('-0.614')), (3, 32, Decimal('-3.83'), Decimal('-0.120')), (15, 82, Decimal('-3.13'), Decimal('-0.038')), (5, 16, Decimal('-3.03'), Decimal('-0.189')), (10, 4, Decimal('-3.01'), Decimal('-0.753')), (2, 25, Decimal('-2.66'), Decimal('-0.106')), (13, 174, Decimal('-1.27'), Decimal('-0.007')), (6, 1, Decimal('-0.64'), Decimal('-0.644')), (1, 29, Decimal('0.25'), Decimal('0.009')), (23, 57, Decimal('0.53'), Decimal('0.009')), (11, 13, Decimal('1.38'), Decimal('0.106')), (18, 53, Decimal('13.13'), Decimal('0.248')), (17, 140, Decimal('17.81'), Decimal('0.127'))]
avg move %, avg win, avg loss, wins, losses: (Decimal('39.34'), Decimal('0.694'), Decimal('-0.775'), 766, 945)

== internationals
recorder: [('UEFA Nations League B', 5), ('Friendlies International', 4), ('CONCACAF Nations League Qualifiers', 2), ('CONCACAF Nations League A', 2), ('UEFA Nations League A', 2), ('CONCACAF Nations League B', 1), ('CAF African Cup of Nations Qualifiers', 1)]
history, international-looking match-odds markets: (68, datetime.datetime(2025, 7, 12, 10, 24, tzinfo=datetime.timezone.utc), datetime.datetime(2026, 9, 30, 1, 0, tzinfo=datetime.timezone.utc))
```
