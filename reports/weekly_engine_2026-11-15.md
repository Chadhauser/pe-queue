# Weekly engine first run — reading 2026-11-15 15:18 UTC (job 582)

## weekly_engine.log
```
== 2026-11-15 00:00 weekly engine ==
Cricket exit 1 RESULT lines 0
Greyhound Racing exit 1 RESULT lines 0
Horse Racing exit 1 RESULT lines 0
Soccer exit 1 RESULT lines 0
Tennis exit 1 RESULT lines 0
/root/pe-sports/team/verifier_cells.py:24: DeprecationWarning: datetime.datetime.utcnow() is deprecated and scheduled for removal in a future version. Use timezone-aware objects to represent datetimes
  print(f"{datetime.datetime.utcnow():%Y-%m-%d %H:%M} passed cells: {n} (fair_factor BETWEEN 0.7 AND 1.3 enforced)"); [print("  ",r) for r in c.fetchall()]
cells dropped by the replay (negative on real books): 0
2026-11-15 00:27 passed cells: 18 (fair_factor BETWEEN 0.7 AND 1.3 enforced)
   ('Soccer', 'BOTH_TEAMS_TO_SCORE', Decimal('0.3'), Decimal('0.35'), 'BACK', 1814, Decimal('0.0212'), Decimal('0.0077'))
   ('Soccer', 'BOTH_TEAMS_TO_SCORE', Decimal('0.65'), Decimal('0.7'), 'LAY', 1856, Decimal('-0.0208'), Decimal('-0.0081'))
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
```
## per-sport logs
### fairprice_weekly_Cricket.log (8 lines, 0 RESULT)
```
Traceback (most recent call last):
  File "/root/pe-sports/team/fairprice_v0.py", line 22, in <module>
    cur.execute("SELECT sport, market_type, count(DISTINCT market_id) FROM bf_hist_other GROUP BY 1,2 HAVING count(DISTINCT market_id)>=200 ORDER BY 1, 3 DESC"); types=cur.fetchall()
    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
psycopg2.OperationalError: server closed the connection unexpectedly
	This probably means the server terminated abnormally
	before or while processing the request.

...
Traceback (most recent call last):
  File "/root/pe-sports/team/fairprice_v0.py", line 22, in <module>
    cur.execute("SELECT sport, market_type, count(DISTINCT market_id) FROM bf_hist_other GROUP BY 1,2 HAVING count(DISTINCT market_id)>=200 ORDER BY 1, 3 DESC"); types=cur.fetchall()
    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
psycopg2.OperationalError: server closed the connection unexpectedly
	This probably means the server terminated abnormally
	before or while processing the request.

```
### fairprice_weekly_Greyhound_Racing.log (8 lines, 0 RESULT)
```
Traceback (most recent call last):
  File "/root/pe-sports/team/fairprice_v0.py", line 22, in <module>
    cur.execute("SELECT sport, market_type, count(DISTINCT market_id) FROM bf_hist_other GROUP BY 1,2 HAVING count(DISTINCT market_id)>=200 ORDER BY 1, 3 DESC"); types=cur.fetchall()
    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
psycopg2.OperationalError: server closed the connection unexpectedly
	This probably means the server terminated abnormally
	before or while processing the request.

...
Traceback (most recent call last):
  File "/root/pe-sports/team/fairprice_v0.py", line 22, in <module>
    cur.execute("SELECT sport, market_type, count(DISTINCT market_id) FROM bf_hist_other GROUP BY 1,2 HAVING count(DISTINCT market_id)>=200 ORDER BY 1, 3 DESC"); types=cur.fetchall()
    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
psycopg2.OperationalError: server closed the connection unexpectedly
	This probably means the server terminated abnormally
	before or while processing the request.

```
### fairprice_weekly_Horse_Racing.log (8 lines, 0 RESULT)
```
Traceback (most recent call last):
  File "/root/pe-sports/team/fairprice_v0.py", line 22, in <module>
    cur.execute("SELECT sport, market_type, count(DISTINCT market_id) FROM bf_hist_other GROUP BY 1,2 HAVING count(DISTINCT market_id)>=200 ORDER BY 1, 3 DESC"); types=cur.fetchall()
    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
psycopg2.OperationalError: server closed the connection unexpectedly
	This probably means the server terminated abnormally
	before or while processing the request.

...
Traceback (most recent call last):
  File "/root/pe-sports/team/fairprice_v0.py", line 22, in <module>
    cur.execute("SELECT sport, market_type, count(DISTINCT market_id) FROM bf_hist_other GROUP BY 1,2 HAVING count(DISTINCT market_id)>=200 ORDER BY 1, 3 DESC"); types=cur.fetchall()
    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
psycopg2.OperationalError: server closed the connection unexpectedly
	This probably means the server terminated abnormally
	before or while processing the request.

```
### fairprice_weekly_Soccer.log (8 lines, 0 RESULT)
```
Traceback (most recent call last):
  File "/root/pe-sports/team/fairprice_v0.py", line 22, in <module>
    cur.execute("SELECT sport, market_type, count(DISTINCT market_id) FROM bf_hist_other GROUP BY 1,2 HAVING count(DISTINCT market_id)>=200 ORDER BY 1, 3 DESC"); types=cur.fetchall()
    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
psycopg2.OperationalError: server closed the connection unexpectedly
	This probably means the server terminated abnormally
	before or while processing the request.

...
Traceback (most recent call last):
  File "/root/pe-sports/team/fairprice_v0.py", line 22, in <module>
    cur.execute("SELECT sport, market_type, count(DISTINCT market_id) FROM bf_hist_other GROUP BY 1,2 HAVING count(DISTINCT market_id)>=200 ORDER BY 1, 3 DESC"); types=cur.fetchall()
    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
psycopg2.OperationalError: server closed the connection unexpectedly
	This probably means the server terminated abnormally
	before or while processing the request.

```
### fairprice_weekly_Tennis.log (8 lines, 0 RESULT)
```
Traceback (most recent call last):
  File "/root/pe-sports/team/fairprice_v0.py", line 22, in <module>
    cur.execute("SELECT sport, market_type, count(DISTINCT market_id) FROM bf_hist_other GROUP BY 1,2 HAVING count(DISTINCT market_id)>=200 ORDER BY 1, 3 DESC"); types=cur.fetchall()
    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
psycopg2.OperationalError: server closed the connection unexpectedly
	This probably means the server terminated abnormally
	before or while processing the request.

...
Traceback (most recent call last):
  File "/root/pe-sports/team/fairprice_v0.py", line 22, in <module>
    cur.execute("SELECT sport, market_type, count(DISTINCT market_id) FROM bf_hist_other GROUP BY 1,2 HAVING count(DISTINCT market_id)>=200 ORDER BY 1, 3 DESC"); types=cur.fetchall()
    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
psycopg2.OperationalError: server closed the connection unexpectedly
	This probably means the server terminated abnormally
	before or while processing the request.

```
## how fairprice_v0.py picks its sport
```
1:# H1 FAIR PRICE v1 (544, 9 Nov 2026): the data tells us the price — every sport, every single-line market the tape covers.
3:# definition). Per (sport, market_type): the last pre-off LTP per runner (closing price), official WINNER/LOSER, complete books only, k =
5:# Calibration by (sport, market_type, probability band): IS = older half by date, OOS = newer half; fair factor = IS rate / IS implied.
7:# random. RESULT lines for cells n>=300 and >=50 each half. One (sport, type) at a time, memory-safe.
22:cur.execute("SELECT sport, market_type, count(DISTINCT market_id) FROM bf_hist_other GROUP BY 1,2 HAVING count(DISTINCT market_id)>=200 ORDER BY 1, 3 DESC"); types=cur.fetchall()
23:print("sport x type combinations:",len(types),"| sports:",sorted({s for s,_,_ in types}),flush=True)
25:ONLY=set(x for x in os.environ.get('FP_SPORTS','').split(',') if x); EXCL=set(x for x in os.environ.get('FP_EXCLUDE','').split(',') if x)
26:if ONLY or EXCL:   # partial run (football first, then the rest): keep the table, replace only these sports' rows
28:    cur.execute("CREATE TABLE IF NOT EXISTS fair_price_calib (sport TEXT, market_type TEXT, band INT, band_lo NUMERIC, band_hi NUMERIC, n_is INT, rate_is NUMERIC, p_mean_is NUMERIC, n_oos INT, rate
29:    cur.execute("ALTER TABLE fair_price_calib ADD COLUMN IF NOT EXISTS sport TEXT; ALTER TABLE fair_price_calib ADD COLUMN IF NOT EXISTS winners_mean NUMERIC")
30:    cur.execute("DELETE FROM fair_price_calib WHERE coalesce(sport,'Soccer') = ANY(%s)",(sorted({t[0] for t in types}),)); con.commit(); print("partial run, sports:",sorted({t[0] for t in types}),f
31:else: cur.execute("DROP TABLE IF EXISTS fair_price_calib; CREATE TABLE fair_price_calib (sport TEXT, market_type TEXT, band INT, band_lo NUMERIC, band_hi NUMERIC, n_is INT, rate_is NUMERIC, p_mean_
33:for sport,mt,nmk in types:
34:    if mt in MULTI_LINE: skipped_ml.append(f"{sport}/{mt}"); continue
37:                 FROM bf_hist_other WHERE sport=%s AND market_type=%s AND NOT inplay AND ltp>1 AND ltp<1000 ORDER BY market_id, sel, ts DESC),
39:                        sum((status='WINNER')::int) OVER (PARTITION BY market_id) AS k FROM bf_hist_result WHERE sport=%s AND market_type=%s AND status IN ('WINNER','LOSER')),
42:    SELECT market_id, market_time, close_ltp, won, k FROM j WHERE n_pre=n_res AND n_res>=2 AND k>=1 AND k<n_res AND book/k BETWEEN 0.95 AND 1.25""",(sport,mt,sport,mt))
44:    if len(df)<1000: print(f"  {sport}/{mt}: {len(df)} runner-rows on complete books — skipped",flush=True); continue
49:    print(f"  {sport}/{mt}: dates {mtime.min():%Y-%m-%d}..{mtime.max():%Y-%m-%d}, split {SPLIT:%Y-%m-%d}, winners/market mean {df.groupby('market_id').k.first().mean():.2f}",flush=True)
54:        rows.append((sport,mt,int(b),edges[b],edges[b+1],int(r.n),float(r.rate),float(r.p_mean),int(o.n) if o is not None else 0,float(o.rate) if o is not None else None,float(o.p_mean) if o is not
55:    if rows: psycopg2.extras.execute_values(cur,"INSERT INTO fair_price_calib (sport,market_type,band,band_lo,band_hi,n_is,rate_is,p_mean_is,n_oos,rate_oos,p_mean_oos,fair_factor,winners_mean) VALU
66:        name=f"H1 {sport} {mt} p{edges[b]:.2f}-{edges[b+1]:.2f} {gdf.side.iloc[0]} at close (IS rate {gdf.fair_rate.iloc[0]:.3f} vs implied {gdf.p_is.iloc[0]:.3f})"
68:    tot_rows+=len(df); print(f"  {sport}/{mt}: {len(df)} runner-rows, {df.market_id.nunique()} books, cells {cells}, {(datetime.datetime.now(datetime.UTC)-T0).seconds}s",flush=True)
71:print("NEXT DOOR (pre-registered): loader captures the runner handicap `hc` so AH/goal-line/handicap books settle (H1d); in-play bands for every sport (H1b extended).")
```
## how it ran on 9 Nov (the run that produced the 18 cells)
```
/root/pe-queue/jobs/510_sports_team_daemon.sh:156:cat > fairprice_v0.py <<'PYFILE'
/root/pe-queue/jobs/510_sports_team_daemon.sh:349: {"id":"H1 fair price v0 (closing price calibration, every soccer market type)","script":"/root/pe-sports/team/fairprice_v0.py","status":"proposed","kind":"sweep","pre_re
/root/pe-queue/jobs/510_sports_team_daemon.sh:352:python3 -m py_compile sports_team.py fairprice_v0.py /root/pe-sports/bookie/bookie_paper.py || exit 1
/root/pe-queue/jobs/511_data_health_fixes.sh:251:  pgrep -f fairprice_v0.py >/dev/null || break
/root/pe-queue/jobs/511_data_health_fixes.sh:254:if pgrep -f fairprice_v0.py >/dev/null; then echo "H1 still running after 100 min; daemon picks up the new feeds at its next restart (keepalive)"; else
/root/pe-queue/jobs/512_h1_diagnose.sh:10:cd /root/pe-sports/team && timeout 2400 python3 -I fairprice_v0.py 2>&1 | grep -v DeprecationWarning | tail -60
/root/pe-queue/jobs/513_h1_rebuild.sh:7:cd /root/pe-sports/team && cp fairprice_v0.py fairprice_v0.py.bak_513
/root/pe-queue/jobs/513_h1_rebuild.sh:8:cat > fairprice_v0.py <<'PYFILE'
-rw-r--r-- 1 root root   612 Nov 10 16:07 /root/pe-sports/team/fairprice_v1_Cricket.log
-rw-r--r-- 1 root root   612 Nov 10 16:12 /root/pe-sports/team/fairprice_v1_Greyhound_Racing.log
-rw-r--r-- 1 root root   612 Nov 10 16:17 /root/pe-sports/team/fairprice_v1_Horse_Racing.log
-rw-r--r-- 1 root root   612 Nov 10 16:22 /root/pe-sports/team/fairprice_v1_Tennis.log
-rw-r--r-- 1 root root 65341 Nov  9 11:22 /root/pe-sports/team/fairprice_v1_football.log
-rw-r--r-- 1 root root   519 Nov  9 11:27 /root/pe-sports/team/fairprice_v1_others.log
-rw-r--r-- 1 root root   612 Nov 15 01:07 /root/pe-sports/team/fairprice_weekly_Cricket.log
-rw-r--r-- 1 root root   612 Nov 15 01:12 /root/pe-sports/team/fairprice_weekly_Greyhound_Racing.log
-rw-r--r-- 1 root root   612 Nov 15 01:17 /root/pe-sports/team/fairprice_weekly_Horse_Racing.log
-rw-r--r-- 1 root root   612 Nov 15 01:22 /root/pe-sports/team/fairprice_weekly_Soccer.log
```
## sports in bf_hist_other
```
[('Soccer', 37705256, datetime.date(2025, 10, 11), datetime.date(2030, 8, 20)), ('Horse Racing', 12448896, datetime.date(2025, 10, 11), datetime.date(2026, 9, 30)), ('Tennis', 2286954, datetime.date(2025, 10, 11), datetime.date(2026, 3, 31)), ('Cricket', 1652820, datetime.date(2025, 10, 11), datetime.date(2026, 9, 30)), ('Greyhound Racing', 1595506, datetime.date(2025, 10, 11), datetime.date(2026, 10, 11))]
passed now: [('Soccer', 18)]
frozen_out rows: 0
```
## memory now
               total        used        free      shared  buff/cache   available
Mem:            7941        3665         171        1586        5997        4275
