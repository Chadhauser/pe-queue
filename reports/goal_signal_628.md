# Why the goal signal sends nothing — 2026-11-17 06:48 UTC

## Where alerts are written
```
/root/pe-brain/repo/brain/monitor_ht.py:245:                    INSERT INTO goal_alerts (
/root/pe-brain/repo/brain/monitor_ht.py:315:                    INSERT INTO goal_alerts (
/root/pe-brain/repo/brain/dry_run.py:5:  - never writes to goal_alerts (DB is read-only access during dry-run)
/root/pe-brain/repo/brain/pattern_matcher.py:209:                        INSERT INTO goal_alerts
```
### /root/pe-brain/repo/brain/monitor_ht.py around the insert
```
29:291-    if real_price is None:
30:292-        return None, None, None, None
36:298-        if not r:
37:299-            return None, None, None, None
38:300-        return r['back_px'], r['lay_px'], r['ts'], r['event_name']
41:303-        return None, None, None, None
49:311-                if rb:
```
## monitor_ht.log since 13 Nov: fired counts and errors
```
4200
[GOAL-SIGNAL] live=38 candidates=34 fired=1 stats_calls=4
[GOAL-SIGNAL] live=37 candidates=30 fired=1 stats_calls=3
[GOAL-SIGNAL] live=138 candidates=101 fired=1 stats_calls=1
[GOAL-SIGNAL] live=19 candidates=15 fired=1 stats_calls=1
[GOAL-SIGNAL] live=3 candidates=3 fired=2 stats_calls=1
[GOAL-SIGNAL] live=12 candidates=8 fired=1 stats_calls=3
[GOAL-SIGNAL] live=3 candidates=1 fired=1 stats_calls=1
[GOAL-SIGNAL] live=3 candidates=1 fired=1 stats_calls=0
      8 Traceback (most recent call last):
      6 [BOOT TEST OK] goal_alerts INSERT/DELETE round-trip succeeded
      4 psycopg2.errors.UniqueViolation: duplicate key value violates unique constraint "goal_alerts_pkey"
      4 [BOOT TEST FAIL] duplicate key value violates unique constraint "goal_alerts_pkey"
      4 ValueError: unsupported format character ''' (0x27) at index 63
```
## brain environment: DB targets (host only), switches
```
#!/bin/bash
# exported fresh at every start so the services follow the database cutover automatically
eval "$(/usr/bin/python3 - <<'PY'
import sys, shlex; sys.path.insert(0,'/root/pe-queue/runner'); import creds
app,user,pw=creds.betfair()
print("export DATABASE_URL="+shlex.quote(creds.pg_railway()))
PY
)"
```
## what writes goal_events (stopped 8 Nov 03:29)
```
/root/pe-logger/profit_hunt.py
2:0 19 * * * /usr/bin/python3 /root/trading/daily_racing_results.py >> /root/logs/racing.log 2>&1
3:0 23 * * * /usr/bin/python3 /root/trading/cricket_results.py >> /root/logs/cricket.log 2>&1
4:0 22 * * * /usr/bin/python3 /root/trading/golf_results.py >> /root/logs/golf_results.log 2>&1
5:30 23 * * * /usr/bin/python3 /root/trading/tennis_results.py >> /root/logs/tennis.log 2>&1
11:#PAUSED-543 40 * * * * cd /root/pe-logger && /usr/bin/python3 racing_results.py >> results.log 2>&1
```
## API-Football results pipeline (scoreboard: BROKEN since 8 Nov)
```
/root/pe-sports/team/sports_team.py:30: ('API-Football results (finished fixtures, 48h)','local',"select count(*) from af_fixtures where kickoff>now()-interval '48 hours' and status in ('FT','AET','PEN')","select max(kickoff) from af_fixtures where status in ('FT','AET','PEN')"),
== /root/pe-queue-logs/240_results_pipeline_to_github.log
waiting for GITHUB_RESULTS_TOKEN in /root/pe-logger/.env
exit=75 secs=0
== /root/pe-hist/results_backfill_tennis2.log
04:24 passed cells by sport: [('Soccer', 16), ('Cricket', 2), ('Greyhound Racing', 1), ('Horse Racing', 1)]
/root/pe-hist/results_backfill.py:78: DeprecationWarning: datetime.datetime.utcnow() is deprecated and scheduled for removal in a future version. Use timezone-aware objects to represent datetimes in UTC: datetime.datetime.now(datetime.UTC).
  f.write(f"# Results backfill and engine, every sport — {datetime.datetime.utcnow():%F %H:%M} UTC\n\n")
04:24 report pushed
== /root/pe-hist/results_backfill.log
22:39 passed cells by sport: [('Soccer', 16), ('Tennis', 3), ('Cricket', 2), ('Greyhound Racing', 1), ('Horse Racing', 1)]
/root/pe-hist/results_backfill.py:75: DeprecationWarning: datetime.datetime.utcnow() is deprecated and scheduled for removal in a future version. Use timezone-aware objects to represent datetimes in UTC: datetime.datetime.now(datetime.UTC).
  f.write(f"# Results backfill and engine, every sport — {datetime.datetime.utcnow():%F %H:%M} UTC\n\n")
22:39 report pushed
```
