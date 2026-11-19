# 671 - 2026-11-19 13:00 UTC
```
friday line patched
compiles
Money: real £0.00, paper £-76.35 across 11 rules.
Proof gate: nearest is desk HT11 (1-1 HT, back O2.5) at 6 of 100 settled, £+2.04. Passed and waiting for your yes: 0 (the auditor confirms each against its history test).
Map: nothing proven yet. 2 days of recorded prices behind it.
Audit: 20 claims checked over 1 nights, 1 mismatches.
== sports per recorder, last 3 days
ip_tape columns:
   ('ts, sport, market_id, event_name, competition, market_type, market_start, status, secs_since_start, sel_id, sel_name, ltp, back_px, back_sz, lay_px, lay_sz, back3_sz, lay3_sz, total_matched',)
in-play recorder by sport, last 3 days:
   ('basketball', 4986990, 329)
   ('american_football', 760074, 15)
   ('tennis', 468908, 1677)
   ('politics', 190719, 5)
   ('ice_hockey', 86905, 51)
   ('cricket', 65268, 61)
   ('golf', 63297, 4)
   ('snooker', 41762, 65)
   ('horse_racing', 39049, 521)
   ('esports', 4242, 8)
   ('volleyball', 3122, 5)
   ('darts', 2236, 40)
   ('swimming', 670, 2)
   ('boxing', 634, 5)
history files by sport (markets with a result):
   ('Soccer', 3319178)
   ('Tennis', 104191)
   ('Greyhound Racing', 38406)
   ('Horse Racing', 27978)
   ('Cricket', 9370)
bf_hist_other columns:
   ('sport text, market_id text, event_id text, event_name text, market_type text, market_time timestamp with time zone, country text, sel text, ts timestamp with time zone, ltp numeric, inplay boolean',)
bf_hist_result columns:
   ('sport text, market_id text, event_id text, market_type text, sel text, status text, settled_time text, market_status text',)
bf_hist_other sample:
   ('Soccer', '1.260227781', '35844518', 'Queen of South v Aberdeen', 'MATCH_ODDS', datetime.datetime(2026, 7, 22, 18, 45, tzinfo=datetime.timezone.utc), 'GB', 'Aberdeen', datetime.datetime(2026, 7, 21, 6, 57, 52, 604000, tzinfo=datetime.timezone.utc), Decimal('1.33'), False)
   ('Soccer', '1.260227781', '35844518', 'Queen of South v Aberdeen', 'MATCH_ODDS', datetime.datetime(2026, 7, 22, 18, 45, tzinfo=datetime.timezone.utc), 'GB', 'Aberdeen', datetime.datetime(2026, 7, 21, 19, 45, 12, 156000, tzinfo=datetime.timezone.utc), Decimal('1.37'), False)
   ('Soccer', '1.260227781', '35844518', 'Queen of South v Aberdeen', 'MATCH_ODDS', datetime.datetime(2026, 7, 22, 18, 45, tzinfo=datetime.timezone.utc), 'GB', 'Aberdeen', datetime.datetime(2026, 7, 22, 4, 23, 16, 224000, tzinfo=datetime.timezone.utc), Decimal('1.36'), False)
xx_tape market names by exchange, last day:
   ('matchbook', 'Match Odds', 2154603)
   ('smarkets', 'Match winner', 168879)
   ('smarkets', 'Set 2 winner', 145246)
   ('smarkets', 'Winner (including overtime)', 94166)
   ('smarkets', 'Set 1 winner', 80576)
   ('smarkets', 'Set 3 winner', 75248)
   ('smarkets', 'Winner and over/under 2.5', 63737)
   ('smarkets', 'Winner and both teams to score', 61180)
   ('smarkets', 'First half winner and both teams to score', 59648)
   ('smarkets', 'Full-time result', 39369)
   ('smarkets', 'Half-time result', 32997)
   ('smarkets', 'Second half result', 27144)
   ('smarkets', 'Draw No Bet', 26214)
   ('smarkets', 'First half winner and over/under 1.5', 16770)
   ('smarkets', 'First Half Winner (3-way)', 10392)
== how the stream picks sports
35:        for m in api(tok,'listMarketCatalogue',{"filter":{"eventTypeIds":["7"],"marketTypeCodes":["WIN"],"marketCountries":["GB","IE"],"marketStartTime":{"from":t0,"to":t1}},"marketProjection":["EVENT","RUNNER_DESCRIP
37:        for m in api(tok,'listMarketCatalogue',{"filter":{"eventTypeIds":["1"],"marketTypeCodes":["MATCH_ODDS","OVER_UNDER_25"],"inPlayOnly":True},"marketProjection":["EVENT","RUNNER_DESCRIPTION","MARKET_START_TIME","
40:        for m in api(tok,'listMarketCatalogue',{"filter":{"eventTypeIds":["2"],"marketTypeCodes":["MATCH_ODDS"],"inPlayOnly":True},"marketProjection":["EVENT","RUNNER_DESCRIPTION","MARKET_START_TIME"],"maxResults":40,
43:        for m in api(tok,'listMarketCatalogue',{"filter":{"eventTypeIds":["1"],"marketTypeCodes":["MATCH_ODDS"],"inPlayOnly":False,"marketStartTime":{"from":t_now,"to":t2}},"marketProjection":["EVENT","RUNNER_DESCRIPT
48:        t0=datetime.datetime.utcnow(); f={"eventTypeIds":["1"],"marketTypeCodes":_passed_types(),"marketStartTime":{"from":t0.strftime('%Y-%m-%dT%H:%M:%SZ'),"to":(t0+datetime.timedelta(hours=2)).strftime('%Y-%m-%dT%H:
== how the other-exchange recorder picks sports
1106 /bin/sh -c /root/pe-xx/keepalive.sh
1119 /bin/bash /root/pe-xx/keepalive.sh
1132 python3 xx_recorder.py
/root/pe-xx/xx_recorder.py:26:SM_SPORT={'football':'football','tennis':'tennis','basketball':'basketball'}
/root/pe-xx/xx_recorder.py:66:MB_SPORT={'football':15,'tennis':9,'basketball':1}
== in-play recorder sports
/root/pe-ip/ip_recorder.py:6:SPORTS={}  # filled dynamically from listEventTypes every catalogue refresh; football (1) excluded (own recorder)
/root/pe-ip/ip_recorder.py:34:        SPORTS={e['eventType']['id']:e['eventType']['name'].lower().replace(' ','_') for e in ets if e['eventType']['id']!='1'}
/root/pe-ip/ip_recorder.py:38:            res=api('listMarketCatalogue',{"filter":{"eventTypeIds":[etid],"inPlayOnly":True},
/root/pe-liq/liq_recorder.py:43:        res=api('listMarketCatalogue',{"filter":{"eventTypeIds":["1"],"marketTypeCodes":[mt,"CORRECT_SCORE"],"marketStartTime":{"from":_win(-4),"to":_win(2)}},
/root/pe-liq/liq_recorder_new.py:41:        res=api('listMarketCatalogue',{"filter":{"eventTypeIds":["1"],"marketTypeCodes":[mt,"CORRECT_SCORE"],"marketStartTime":{"from":_win(-4),"to":_win(2)}},
== paused sport lines (543)
#PAUSED-543 @reboot cd ~/pe-logger && nohup python3 server_price_logger.py >> logger.log 2>&1 &
#PAUSED-543 @reboot cd ~/pe-logger && nohup python3 racing_price_logger.py >> racing.log 2>&1 &
#PAUSED-543 @reboot cd ~/pe-logger && nohup python3 tennis_price_logger.py >> tennis.log 2>&1 &
#PAUSED-543 15 2 * * * cd /root/pe-logger && /usr/bin/python3 profit_hunt.py >> hunt.log 2>&1
#PAUSED-543 40 * * * * cd /root/pe-logger && /usr/bin/python3 racing_results.py >> results.log 2>&1
#PAUSED-543 45 2 * * * /root/pe-logger/cs_dutch_paper.sh >> /root/pe-logger/csdutch.log 2>&1
#PAUSED-543 45 2 * * * /root/pe-logger/cs_dutch_paper.sh >> /root/pe-logger/csdutch.log 2>&1
#PAUSED-543 @reboot cd /root/pe-logger && nohup python3 golf_price_logger.py >> golf.log 2>&1 &
#PAUSED-543 50 2 * * * /root/pe-logger/tennis_lay_paper.sh >> /root/pe-logger/tennislay.log 2>&1
#PAUSED-543 @reboot cd /root/pe-tennis && nohup python3 tennis_bot.py >> tennis.log 2>&1 &
#PAUSED-543 50 2 * * * cd /root/pe-logger && python3 cs_map_refresh.py >> csq.log 2>&1 && python3 cs_q_paper.py >> csq.log 2>&1
#PAUSED-543 * * * * * /root/pe-race/keepalive.sh
#PAUSED-543 35 4 * * * cd /root/pe-race && python3 retention.py >> race.log 2>&1
#PAUSED-543 * * * * * /root/pe-tennis2/keepalive.sh
#PAUSED-543 50 5 * * * cd /root/pe-tennis2 && python3 settle.py >> dog.log 2>&1
#PAUSED-543 * * * * * /root/pe-cricket/keepalive.sh
#PAUSED-543 55 5 * * * cd /root/pe-cricket && python3 settle.py >> cricket.log 2>&1
#PAUSED-543 45 4 * * * cd /root/pe-cricket && python3 -c "import sys,psycopg2;sys.path.insert(0,'/root/pe-bot');from bot_core import DB;c=psycopg2.con
#PAUSED-543 * * * * * /root/pe-race/keepalive_mm.sh
#PAUSED-543 * * * * * /root/pe-race/keepalive_mm_stream.sh
#PAUSED-543 * * * * * /root/pe-race/keepalive_mm_size.sh
#PAUSED-543 50 3 * * * python3 /root/pe-race/mm_kpis.py > /root/pe-race/mm_kpis.txt 2>&1
```
