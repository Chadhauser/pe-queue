# 649 — 2026-11-17 14:36 UTC
```
compiles
624:*/5 * * * * pgrep -f v3_recorder.py >/dev/null || nohup /root/pe-sports/team/run_v3_recorder.sh >/dev/null 2>&1 &   # 649 v3 forward paper recorder
625:10 7 * * * /root/pe-sports/team/run_v3_settle.sh   # 649 v3 forward paper settle
recorder processes: 1
heartbeat: [(1, datetime.datetime(2026, 11, 17, 14, 38, 30, 490490, tzinfo=datetime.timezone.utc), 0, 0, 'due 0')]
snap rows/markets: (0, 0)
--- first settle run (backfills football-data; no bets expected before Pinnacle closing for 17 Nov+ is published)

Betfair markets recorded 1-3 min before the off: 0 (None to None). football-data rows refreshed: 2306; Pinnacle closing available up to 2026-01-14.
Matched to a Pinnacle closing price this run: 0; new paper bets: 0.

| rule | settled | won | £ at £2 | per £100 | first half £ | second half £ | towards 100 |
|---|---|---|---|---|---|---|---|
| R1 home LAY 2% | 0 | 0 | £+0.00 | £+0.0 | £+0.00 | £+0.00 | 0 of 100 |
| R2 home BACK 5% | 0 | 0 | £+0.00 | £+0.0 | £+0.00 | £+0.00 | 0 of 100 |
```
