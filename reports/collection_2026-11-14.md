# Collection reading — 2026-11-14 08:42 UTC (job 571)

## 1. Sports on each tape

### liq_sample (sport column: None)
no sport column — rows 24 h: 3596372

### stream_ticks (sport column: sport)
| sport | rows last 24 h | rows last 7 d | markets 7 d |
|---|---|---|---|
| football | 5316587 | 30163613 | 4433 |
| tennis | 684799 | 10130445 | 507 |
| racing | 973718 | 5367118 | 99 |

### ip_tape (sport column: sport)
| sport | rows last 24 h | rows last 7 d | markets 7 d |
|---|---|---|---|
| basketball | 3071242 | 15945363 | 595 |
| american_football | 427338 | 2731756 | 43 |
| tennis | 114022 | 1219128 | 3034 |
| golf | 405967 | 879771 | 9 |
| politics | 68350 | 589032 | 6 |
| ice_hockey | 76711 | 460894 | 119 |
| cricket | 24862 | 191876 | 100 |
| horse_racing | 23026 | 159573 | 1159 |
| esports | 5518 | 42506 | 43 |
| snooker | 770 | 14128 | 18 |
| volleyball | 0 | 8956 | 7 |
| darts | 986 | 4220 | 88 |
| boxing | 0 | 2397 | 8 |
| rugby_union | 2145 | 2145 | 3 |
| australian_rules | 630 | 630 | 2 |

### xx_tape (sport column: sport)
| sport | rows last 24 h | rows last 7 d | markets 7 d |
|---|---|---|---|
| football | 3142997 | 15259020 | 11814 |
| tennis | 334913 | 2763422 | 20668 |
| basketball | 243407 | 875560 | 10896 |

Betfair event types with markets on the exchange this week (from bf_hist_other / catalogue tables if present): [('Soccer',)]

## 2. Archive (the 02:35 UTC job)

Code path (archive_tape.py, job 548): per table per day — COPY to zstd file, count lines in the file, DELETE only if file rows == table rows, else keep rows and remove the file. Nothing is deleted unverified.

- liq_sample: 9 daily files, 0.4 GB, 2026-10-31.csv.zst .. 2026-11-08.csv.zst
- ip_tape: 9 daily files, 0.2 GB, 2026-10-31.csv.zst .. 2026-11-08.csv.zst
- stream_ticks: 7 daily files, 0.8 GB, 2026-11-02.csv.zst .. 2026-11-08.csv.zst

archive.log tail:
stream_ticks 2026-11-07: 10838875 rows -> /root/pe-archive/stream_ticks/2026-11-07.csv.zst (166 MB), deleted
stream_ticks: vacuumed
ip_tape 2026-11-07: 8706348 rows -> /root/pe-archive/ip_tape/2026-11-07.csv.zst (24 MB), deleted
ip_tape: vacuumed
liq_sample 2026-11-07: 5956065 rows -> /root/pe-archive/liq_sample/2026-11-07.csv.zst (82 MB), deleted
liq_sample: vacuumed
stream_ticks 2026-11-08: 17745707 rows -> /root/pe-archive/stream_ticks/2026-11-08.csv.zst (186 MB), deleted
stream_ticks: vacuumed
ip_tape 2026-11-08: 7814748 rows -> /root/pe-archive/ip_tape/2026-11-08.csv.zst (22 MB), deleted
ip_tape: vacuumed
liq_sample 2026-11-08: 11277293 rows -> /root/pe-archive/liq_sample/2026-11-08.csv.zst (130 MB), deleted
liq_sample: vacuumed

crontab archive lines:
#PAUSED-543 45 4 * * * cd /root/pe-cricket && python3 -c "import sys,psycopg2;sys.path.insert(0,'/root/pe-bot');from bot_core import DB;c=psycopg2.connect(DB,sslmode='require');c.autocommit=True;c.cursor().execute(\"DELETE FROM cricket_fav_tape WHERE ts<now()-interval '14 days'\")" >> cricket.log 2>&1
35 3 * * * KEEP_DAYS=5 timeout 7000 /usr/bin/python3 /root/pe-archive/archive_tape.py >> /root/pe-archive/archive.log 2>&1

Oldest row still in each tape (KEEP window): [(datetime.date(2026, 11, 9), datetime.date(2026, 11, 9), datetime.date(2026, 11, 9))]

The 'tape_archive_wm' watermark the Watchman reports as stuck at 12 Nov belongs to tape_archive.py — the hourly Railway-to-local copier removed in job 553 because source and destination became the same table. It is not the archive above.

## 3. The 17 dropped tables (dumps in /root/pe-archive/tables)

| table | dump size MB | restorable | what it held |
|---|---|---|---|
| af_events | 18 | present now | API-Football events (RESTORED) |
| af_stats | 8 | dropped | API-Football match stats |
| bf_golf_log | 10 | dropped |  |
| bf_price_log | 221 | dropped | pre-off price log, old recorder (pre stream) |
| bf_racing_log | 83 | dropped | racing price log, old recorder |
| bf_tennis_log | 70 | dropped | tennis price log, old recorder |
| bfsp_history | 19 | dropped | Betfair SP history (racing) |
| ch_accounts | 30 | dropped |  |
| factory_trades | 7 | dropped |  |
| fd_matches | 36 | dropped | football-data results |
| finder_rlog | 62 | dropped |  |
| finder_tlog | 53 | dropped |  |
| goal_live_predictions | 44 | present now | goal engine predictions (RESTORED 13 Nov) |
| goal_timeline | 32 | present now | goal engine timeline (RESTORED) |
| racing_tape | 11 | dropped | racing in-play tape, old recorder |
| runners | 11 | dropped | racing runners |
| xx_ip_331 | 8 | dropped |  |

## 4. Disk

Disk: 155 GB total, 16.3 GB free. Database: 104.2 GB. Archive files: 2.1 GB.

Daily growth (archive file sizes per day, i.e. what one day of tape costs on disk once compressed):
- liq_sample: 2026-11-04 16 MB, 2026-11-05 36 MB, 2026-11-06 1 MB, 2026-11-07 82 MB, 2026-11-08 130 MB
- ip_tape: 2026-11-04 14 MB, 2026-11-05 12 MB, 2026-11-06 0 MB, 2026-11-07 24 MB, 2026-11-08 22 MB
- stream_ticks: 2026-11-04 116 MB, 2026-11-05 127 MB, 2026-11-06 1 MB, 2026-11-07 166 MB, 2026-11-08 186 MB

Uncompressed in the database, per day (last full day):
- liq_sample: 7.2 GB for 13641031 rows -> about 1.91 GB per day at today's 3606160 rows/day
- ip_tape: 11.4 GB for 22254651 rows -> about 2.17 GB per day at today's 4224047 rows/day
- stream_ticks: 16.9 GB for 45671494 rows -> about 2.58 GB per day at today's 6985582 rows/day
- xx_tape: 6.6 GB for 30416210 rows -> about 0.81 GB per day at today's 3725991 rows/day

## Disk history (df, from the Watchman reports in the repo)
15 GB free 11 GB free 5.6 GB free 7.3 GB free 5.8 GB free 6.7 GB free 7.4 GB free 8.3 GB free 8.6 GB free 8.9 GB free 9.1 GB free 9.1 GB free 9.0 GB free 8.9 GB free 5.9 GB free 6.1 GB free 20 GB free 6.6 GB free 6.7 GB free 6.8 GB free 6.6 GB free 6.9 GB free 8.0 GB free 8.1 GB free 8.3 GB free 8.4 GB free 9.0 GB free 8.8 GB free 8.8 GB free 7.9 GB free 8.3 GB free 8.5 GB free 8.8 GB free 8.9 GB free 8.8 GB free 8.7 GB free 6.3 GB free 5.3 GB free 5.6 GB free 5.8 GB free 
## Stream recorder subscription
        for m in api(tok,'listMarketCatalogue',{"filter":{"eventTypeIds":["7"],"marketTypeCodes":["WIN"],"marketCountries":["GB","IE"],"marketStartTime":{"from":t0,"to":t1}},"marketProjection":["EVENT
        for m in api(tok,'listMarketCatalogue',{"filter":{"eventTypeIds":["1"],"marketTypeCodes":["MATCH_ODDS","OVER_UNDER_25"],"inPlayOnly":True},"marketProjection":["EVENT","RUNNER_DESCRIPTION","MAR
        for m in api(tok,'listMarketCatalogue',{"filter":{"eventTypeIds":["2"],"marketTypeCodes":["MATCH_ODDS"],"inPlayOnly":True},"marketProjection":["EVENT","RUNNER_DESCRIPTION","MARKET_START_TIME"]
        for m in api(tok,'listMarketCatalogue',{"filter":{"eventTypeIds":["1"],"marketTypeCodes":["MATCH_ODDS"],"inPlayOnly":False,"marketStartTime":{"from":t_now,"to":t2}},"marketProjection":["EVENT"
        t0=datetime.datetime.utcnow(); f={"eventTypeIds":["1"],"marketTypeCodes":_passed_types(),"marketStartTime":{"from":t0.strftime('%Y-%m-%dT%H:%M:%SZ'),"to":(t0+datetime.timedelta(hours=2)).strft
