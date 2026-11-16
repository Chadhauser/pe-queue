# Stale services check — 2026-11-16 18:02 UTC

## 1. Job 613 (execution methods)
NOT running
```
2026-11-02.csv.zst 5944804 {'M1': 1, 'M2_0.01': 1, 'M2_0.02': 1, 'M3_0.01': 1, 'M3_0.02': 1, 'M4_0.01': 1, 'M4_0.02': 1}
2026-11-03.csv.zst 14256224 {'M1': 4, 'M2_0.01': 4, 'M2_0.02': 4, 'M3_0.01': 4, 'M3_0.02': 4, 'M4_0.01': 3, 'M4_0.02': 3}
2026-11-04.csv.zst 22052760 {'M1': 7, 'M2_0.01': 7, 'M2_0.02': 7, 'M3_0.01': 8, 'M3_0.02': 8, 'M4_0.01': 4, 'M4_0.02': 4}
2026-11-05.csv.zst 30322650 {'M1': 12, 'M2_0.01': 12, 'M2_0.02': 12, 'M3_0.01': 14, 'M3_0.02': 14, 'M4_0.01': 8, 'M4_0.02': 8}
2026-11-06.csv.zst 30412140 {'M1': 12, 'M2_0.01': 12, 'M2_0.02': 12, 'M3_0.01': 14, 'M3_0.02': 14, 'M4_0.01': 8, 'M4_0.02': 8}
2026-11-07.csv.zst 41251015 {'M1': 17, 'M2_0.01': 17, 'M2_0.02': 17, 'M3_0.01': 19, 'M3_0.02': 19, 'M4_0.01': 11, 'M4_0.02': 11}
2026-11-08.csv.zst 58996722 {'M1': 18, 'M2_0.01': 18, 'M2_0.02': 18, 'M3_0.01': 23, 'M3_0.02': 23, 'M4_0.01': 12, 'M4_0.02': 12}
2026-11-09.csv.zst 68419100 {'M1': 20, 'M2_0.01': 20, 'M2_0.02': 20, 'M3_0.01': 25, 'M3_0.02': 25, 'M4_0.01': 14, 'M4_0.02': 14}
2026-11-10.csv.zst 78071738 {'M1': 37, 'M2_0.01': 36, 'M2_0.02': 32, 'M3_0.01': 60, 'M3_0.02': 52, 'M4_0.01': 39, 'M4_0.02': 39}
Traceback (most recent call last):
  File "/root/pe-sports/team/execution_methods.py", line 80, in <module>
    cur.execute("SELECT ts_recv, market_id, sport, mkt, sel_id, back_px, back_sz, lay_px, lay_sz, ltp, inplay, secs_to_off FROM stream_ticks WHERE secs_to_off BETWEEN 0 AND 3600 ORDER BY ts_recv")
psycopg2.ProgrammingError: can't use a named cursor outside of transactions
```

## 2. Stale heartbeats
### espn
- processes: 0
- scripts that mention heartbeat 'espn':
### xg
- processes: 0
- scripts that mention heartbeat 'xg':
### brain
- processes: 0
- scripts that mention heartbeat 'brain':
### monitor_ht
- processes: 0
- scripts that mention heartbeat 'monitor_ht':
### stats_collector
- processes: 0
- scripts that mention heartbeat 'stats_collector':
### goal_monitor
- processes: 0
- scripts that mention heartbeat 'goal_monitor':
### goal_signal
- processes: 0
- scripts that mention heartbeat 'goal_signal':

### pe-brain launchers
-rwxr-xr-x 1 root root 638 Nov  9 11:01 /root/pe-brain/env.sh
-rwxr-xr-x 1 root root 264 Nov  9 11:01 /root/pe-brain/run_monitor_ht.sh
-rwxr-xr-x 1 root root 284 Nov  9 11:01 /root/pe-brain/run_stats_collector.sh
#### /root/pe-brain/run_monitor_ht.sh
```
#!/bin/bash
cd /root/pe-brain/repo && while true; do source /root/pe-brain/env.sh; /root/pe-brain/venv/bin/python -u brain/monitor_ht.py >> /root/pe-brain/monitor_ht.log 2>&1; echo "$(date -u) monitor_ht exited $?" >> /root/pe-brain/monitor_ht.log; sleep 20; done
```
foreground 25 s:
```
exit 0
```
#### /root/pe-brain/run_stats_collector.sh
```
#!/bin/bash
cd /root/pe-brain/repo && while true; do source /root/pe-brain/env.sh; /root/pe-brain/venv/bin/python -u brain/stats_collector.py >> /root/pe-brain/stats_collector.log 2>&1; echo "$(date -u) stats_collector exited $?" >> /root/pe-brain/stats_collector.log; sleep 20; done
```
foreground 25 s:
```
exit 0
```
### other launchers mentioning espn / xg / goal
### last log lines
#### /root/pe-brain/stats_collector.log
```

[SITECUSTOMIZE] Telegram kill switch ACTIVE — api.telegram.org traffic swallowed (web app is the output surface)
stats: using key from APIFOOTBALL_KEY
stats: collector up, 24 leagues allowed
stats: 5 live in allowed leagues (9 total, 6647 calls left)
stats: ERROR duplicate key value violates unique constraint "goal_stats_live_pkey"
DETAIL:  Key (id)=(21971) already exists.

```
#### /root/pe-brain/monitor_ht.log
```
    bands = calibration_bands(hours_back)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/root/pe-brain/repo/brain/calibrate_goal_model.py", line 127, in calibration_bands
    sql = """
          ^^^
ValueError: unsupported format character ''' (0x27) at index 63
[MATCH_STATS] F1638605 HTTP 200 results=0 rl=69021
[GOAL-SIGNAL] live=3 candidates=3 fired=2 stats_calls=1
```
#### /root/pe-xg/xg.log
```
loop InterfaceError('cursor already closed')
loop InterfaceError('cursor already closed')
loop InterfaceError('cursor already closed')
loop OperationalError('SSL connection has been closed unexpectedly\n')
loop OperationalError('SSL SYSCALL error: EOF detected\n')
loop InterfaceError('cursor already closed')
loop OperationalError('SSL connection has been closed unexpectedly\n')
loop OperationalError('SSL connection has been closed unexpectedly\n')
```
#### /root/pe-xg/late_over_live.log
```
EXIT Chapecoense v Vasco da Gama lay 4.3 -> back 2.76 = -1.12 (dry)
LAY OVER2.5 Tenerife v AD Ceuta FC [Spanish Segunda Division] 70' goals 1 @ 3.85 x £2.0 (dry)
EXIT Tenerife v AD Ceuta FC lay 3.85 -> back 14.0 = +1.42 (dry)
LAY OVER2.5 Granada v Las Palmas [Spanish Segunda Division] 70' goals 1 @ 3.95 x £2.0 (dry)
LAY OVER2.5 Eibar v Cadiz [Spanish Segunda Division] 70' goals 1 @ 4.0 x £2.0 (dry)
GOAL seen Eibar v Cadiz over 6.2->2.08
EXIT Eibar v Cadiz lay 4.0 -> back 2.04 = -1.92 (dry)
loop OperationalError('SSL connection has been closed unexpectedly\n')
```
#### /root/pe-xg/late_over.log
```
EXIT GOAL 1.265227197 4.5->2.78 -6.19
LAY OVER2.5 Tenerife v AD Ceuta FC [Spanish Segunda Division] 71' goals 1 (espn) @ 4.6 (£100.17)
EXIT GOAL 1.265488714 4.6->4.6 +0.00
LAY OVER2.5 Granada v Las Palmas [Spanish Segunda Division] 70' goals 1 (espn) @ 4.0 (£30.0)
EXIT GOAL 1.265262932 4.0->34 +8.65
LAY OVER2.5 Eibar v Cadiz [Spanish Segunda Division] 70' goals 1 (espn) @ 4.3 (£38.61)
EXIT GOAL 1.265271026 4.3->2 -11.50
loop OperationalError('SSL connection has been closed unexpectedly\n')
```
#### /root/pe-sports/team/goal_alert_mail.log
```
```
#### /root/pe-xg/s9.log
```
loop OperationalError('SSL connection has been closed unexpectedly\n')
loop OperationalError('SSL connection has been closed unexpectedly\n')
loop OperationalError('SSL connection has been closed unexpectedly\n')
loop OperationalError('SSL connection has been closed unexpectedly\n')
loop OperationalError('SSL connection has been closed unexpectedly\n')
loop OperationalError('SSL connection has been closed unexpectedly\n')
loop OperationalError('SSL connection has been closed unexpectedly\n')
loop OperationalError('SSL connection has been closed unexpectedly\n')
```

## 3. In-play engine connection drop
file: /root/pe-sports/team/fairprice_inplay.py
```
    for lim,inc in LADDER:
        if p<lim: return inc
    return 10
def vtick(p):
    inc=np.full(len(p),10.0);
    for lim,i in reversed(LADDER): inc=np.where(p<lim,i,inc)
    return inc
def tick_down(p): return np.round(np.maximum(1.01,p-vtick(p-1e-9)),2)
def tick_up(p): return np.round(np.minimum(1000,p+vtick(p)),2)
def tstat(a): a=np.asarray(a,float); return float(a.mean()/(a.std(ddof=1)/math.sqrt(len(a)))) if len(a)>5 and a.std()>0 else 0.0
edges=[0,0.03,0.06,0.10,0.15,0.20,0.25,0.30,0.35,0.40,0.45,0.50,0.55,0.60,0.65,0.70,0.80,0.90,1.0001]
con=psycopg2.connect(creds.pg_local(),sslmode='disable'); cur=con.cursor(); cur.execute("SET statement_timeout=0; SET work_mem='512MB'")
cur.execute("SELECT market_type, count(DISTINCT market_id) FROM bf_hist_other WHERE sport='Soccer' GROUP BY 1 ORDER BY 2 DESC"); types=cur.fetchall(); print("types:",types,flush=True)
cur.execute("DROP TABLE IF EXISTS fair_price_calib_inplay; CREATE TABLE fair_price_calib_inplay (market_type TEXT, band INT, band_lo NUMERIC, band_hi NUMERIC, n_is INT, rate_is NUMERIC, p_mean_is NUMERIC, n_oos INT, rate_oos NUMERIC, p_mean_oos NUMERIC, fair_factor NUMERIC, built_at TIMESTAMPTZ DEFAULT now())"); con.commit()
T0=datetime.datetime.now(datetime.UTC); out=0; tot_rows=0; tot_dropped=0
MULTI_LINE={'ASIAN_HANDICAP','GOAL_LINE','ASIAN_HANDICAP_HT','HANDICAP','CORNER_HANDICAP','ALT_TOTAL_GOALS','ALT_CORNERS','ALT_BOOKINGS','CORRECT_SCORE2'}  # several winners per market; need line-aware settlement (H1d)
for mt,nmk in types:
    if mt in MULTI_LINE: print(f'  {mt}: multi-line market, deferred to H1d',flush=True); continue
    cur.execute("""
    WITH ip AS (SELECT DISTINCT ON (market_id, sel, mb) market_id, sel, mb, market_time, ltp AS close_ltp FROM (
                  SELECT market_id, sel, market_time, ltp, ts, width_bucket(EXTRACT(EPOCH FROM (ts-market_time))/60, ARRAY[1,16,31,46,61,76,91]) AS mb
                  FROM bf_hist_other WHERE sport='Soccer' AND market_type=%s AND inplay AND ltp>1 AND ltp<1000 AND ts>market_time AND ts<market_time+interval '125 minutes') x
                WHERE mb BETWEEN 1 AND 6 ORDER BY market_id, sel, mb, ts DESC),
         res AS (SELECT market_id, sel, (status='WINNER')::int AS won, count(*) OVER (PARTITION BY market_id) AS n_res FROM bf_hist_result WHERE market_type=%s AND status IN ('WINNER','LOSER')),
         j AS (SELECT ip.market_id, ip.mb, ip.market_time, ip.close_ltp::float8 AS close_ltp, res.won, res.n_res, count(*) OVER (PARTITION BY ip.market_id, ip.mb) AS n_pre,
                      sum(1/ip.close_ltp::float8) OVER (PARTITION BY ip.market_id, ip.mb) AS book FROM ip JOIN res USING (market_id, sel))
```
postgres settings:
```
idle_in_transaction_session_timeout|0|ms
maintenance_work_mem|262144|kB
max_connections|100|
shared_buffers|196608|8kB
statement_timeout|0|ms
temp_file_limit|-1|kB
work_mem|65536|kB
```
postgres log (crashes, kills, OOM, terminations) today:
```
2026-11-16 11:06:08.986 CET [1702929] pe@petrade FATAL:  terminating connection due to administrator command
2026-11-16 11:06:08.986 CET [1705496] pe@petrade FATAL:  terminating connection due to administrator command
2026-11-16 11:06:08.986 CET [209188] pe@petrade FATAL:  terminating connection due to administrator command
2026-11-16 11:06:08.986 CET [1483108] pe@petrade FATAL:  terminating connection due to administrator command
2026-11-16 11:06:08.987 CET [467956] pe@petrade FATAL:  terminating connection due to administrator command
2026-11-16 11:06:08.987 CET [1483110] pe@petrade FATAL:  terminating connection due to administrator command
2026-11-16 11:06:08.987 CET [4138024] pe@petrade FATAL:  terminating connection due to administrator command
2026-11-16 11:06:08.987 CET [4121803] pe@petrade FATAL:  terminating connection due to administrator command
2026-11-16 11:06:08.986 CET [4121747] pe@petrade FATAL:  terminating connection due to administrator command
2026-11-16 11:06:08.988 CET [1483109] pe@petrade FATAL:  terminating connection due to administrator command
2026-11-16 11:06:08.989 CET [1705497] pe@petrade FATAL:  terminating connection due to administrator command
2026-11-16 11:06:08.989 CET [545461] pe@petrade FATAL:  terminating connection due to administrator command
2026-11-16 11:06:08.989 CET [4121743] pe@petrade FATAL:  terminating connection due to administrator command
2026-11-16 11:06:08.985 CET [1236213] pe@petrade FATAL:  terminating connection due to administrator command
2026-11-16 11:06:08.989 CET [1705498] pe@petrade FATAL:  terminating connection due to administrator command
2026-11-16 11:20:02.060 CET [1248221] root@root FATAL:  role "root" does not exist
2026-11-16 11:20:02.203 CET [1248242] root@root FATAL:  role "root" does not exist
2026-11-16 12:20:02.199 CET [1261653] root@root FATAL:  role "root" does not exist
2026-11-16 12:20:02.387 CET [1261672] root@root FATAL:  role "root" does not exist
2026-11-16 13:20:01.922 CET [1274119] root@root FATAL:  role "root" does not exist
2026-11-16 13:20:02.021 CET [1274125] root@root FATAL:  role "root" does not exist
2026-11-16 14:20:02.722 CET [1293050] root@root FATAL:  role "root" does not exist
2026-11-16 14:20:03.054 CET [1293061] root@root FATAL:  role "root" does not exist
2026-11-16 15:20:01.957 CET [1319691] root@root FATAL:  role "root" does not exist
2026-11-16 15:20:02.183 CET [1319709] root@root FATAL:  role "root" does not exist
```
kernel OOM today:
```
```
free -g:
```
               total        used        free      shared  buff/cache   available
Mem:              17           3          10           1           5          14
Swap:              3           0           3
```
