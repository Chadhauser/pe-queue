# 659 — 2026-11-19 06:56 UTC
```
== processes
   1135    20:40:05 python3 stream_client.py
  16101    20:30:27 /bin/bash /root/pe-sports/bookie/run_bookie_v2.sh
  16102    20:30:27 python3 bookie_v2.py
== bookie_v2 log
== v3 recorder log
== book recorder log
2026-11-18 08:49:13 events 18 markets 358
2026-11-18 08:59:17 events 18 markets 355
2026-11-18 09:09:23 events 22 markets 433
2026-11-18 09:19:30 events 22 markets 422
2026-11-18 09:29:37 events 24 markets 461
== crontab (ours)
*/5 * * * * pgrep -f 'bookie_v2.py' >/dev/null || nohup /root/pe-sports/bookie/run_bookie_v2.sh >/dev/null 2>&1 &
*/5 * * * * pgrep -f 'brain/monitor_ht.py' >/dev/null || nohup /root/pe-brain/run_monitor_ht.sh >/dev/null 2>&1 &
7 * * * * timeout 3000 /usr/bin/python3 /root/pe-migrate/sync_railway.py goal_alerts,m1_alerts,real_trades >> /root/pe-migrate/sync.cron.log 2>&1
*/2 * * * * /root/pe-sports/team/goal_alert_mail.sh
*/5 * * * * pgrep -f small_bites_live.py >/dev/null || nohup /root/pe-sports/team/run_small_bites_live.sh >/dev/null 2>&1 &   # 626 small bites forward paper
*/5 * * * * pgrep -f v3_recorder.py >/dev/null || nohup /root/pe-sports/team/run_v3_recorder.sh >/dev/null 2>&1 &   # 649 v3 forward paper recorder
10 7 * * * /root/pe-sports/team/run_v3_settle.sh   # 649 v3 forward paper settle
*/5 * * * * pgrep -f coherence_paper.py >/dev/null || nohup /root/pe-sports/team/run_coherence_paper.sh >/dev/null 2>&1 &   # 654 coherence forward paper
15 7 * * * /root/pe-sports/team/coherence_report.sh   # 654 coherence paper report
*/5 * * * * pgrep -f book_recorder.py >/dev/null || nohup /root/pe-sports/team/run_book_recorder.sh >/dev/null 2>&1 &   # 655 THE recorder
== goal monitor files
-rw-r--r-- 1 root root         4 Nov 13 14:54 goal_alert_mail.last
-rw-r--r-- 1 root root         0 Nov 13 14:54 goal_alert_mail.log
-rw-r--r-- 1 root root      1848 Nov 13 14:54 goal_alert_mail.py
-rwxr-xr-x 1 root root       172 Nov 13 14:54 goal_alert_mail.sh
book heartbeat: [(1, datetime.datetime(2026, 11, 18, 9, 35, 53, 52524, tzinfo=datetime.timezone.utc), 461, 0, 'due 0')]
book_snap by day (rows, markets, events):
   (datetime.date(2026, 11, 17), 168199, 556, 22)
   (datetime.date(2026, 11, 18), 612391, 1051, 41)
bookie_paper by day/version:
   (datetime.date(2026, 11, 15), 'v2', 13, 13, Decimal('-2.62'))
   (datetime.date(2026, 11, 16), 'v2', 27, 26, Decimal('3.18'))
   (datetime.date(2026, 11, 17), 'v2', 5, 5, Decimal('2.24'))
   (datetime.date(2026, 11, 17), 'v2.2', 12, 12, Decimal('-15.64'))
   (datetime.date(2026, 11, 18), 'v2.2', 28, 28, Decimal('-2.77'))
   (datetime.date(2026, 11, 19), 'v2.2', 5, 4, Decimal('0.16'))
bookie last bet: [(datetime.datetime(2026, 11, 19, 5, 29, 1, 993269, tzinfo=datetime.timezone.utc),)]
fair_price_passed rows: [(20,)] blocked: [(6,)]
small bites by day:
Traceback (most recent call last):
  File "<stdin>", line 9, in <module>
  File "<stdin>", line 3, in <lambda>
psycopg2.errors.UndefinedColumn: column "ts" does not exist
LINE 1: SELECT ts::date, count(*), round(coalesce(sum(pnl),0),2) FRO...
               ^

```
