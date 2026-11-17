# 635 — 2026-11-17 07:04 UTC
```
--- all cron lines paused by 543
6:#PAUSED-543 @reboot cd ~/pe-logger && nohup python3 server_price_logger.py >> logger.log 2>&1 &
7:#PAUSED-543 @reboot cd ~/pe-logger && nohup python3 racing_price_logger.py >> racing.log 2>&1 &
8:#PAUSED-543 @reboot cd ~/pe-logger && nohup python3 tennis_price_logger.py >> tennis.log 2>&1 &
10:#PAUSED-543 15 2 * * * cd /root/pe-logger && /usr/bin/python3 profit_hunt.py >> hunt.log 2>&1
11:#PAUSED-543 40 * * * * cd /root/pe-logger && /usr/bin/python3 racing_results.py >> results.log 2>&1
27:#PAUSED-543 45 2 * * * /root/pe-logger/cs_dutch_paper.sh >> /root/pe-logger/csdutch.log 2>&1
28:#PAUSED-543 45 2 * * * /root/pe-logger/cs_dutch_paper.sh >> /root/pe-logger/csdutch.log 2>&1
29:#PAUSED-543 @reboot cd /root/pe-logger && nohup python3 golf_price_logger.py >> golf.log 2>&1 &
30:#PAUSED-543 50 2 * * * /root/pe-logger/tennis_lay_paper.sh >> /root/pe-logger/tennislay.log 2>&1
31:#PAUSED-543 @reboot cd /root/pe-push && nohup python3 send_push.py >> push.log 2>&1 &
32:#PAUSED-543 @reboot cd /root/pe-bot && nohup python3 trade_bot.py >> bot.log 2>&1 &
33:#PAUSED-543 @reboot cd /root/pe-tennis && nohup python3 tennis_bot.py >> tennis.log 2>&1 &
34:#PAUSED-543 50 2 * * * cd /root/pe-logger && python3 cs_map_refresh.py >> csq.log 2>&1 && python3 cs_q_paper.py >> csq.log 2>&1
41:#PAUSED-543 0 7 * * * cd /root/pe-prematch && python3 fts_collector.py morning >> prematch.log 2>&1
42:#PAUSED-543 15 7 * * * cd /root/pe-prematch && python3 prematch_bot.py morning >> prematch.log 2>&1
43:#PAUSED-543 30 23 * * * cd /root/pe-prematch && python3 fts_collector.py evening >> prematch.log 2>&1
44:#PAUSED-543 45 23 * * * cd /root/pe-prematch && python3 prematch_bot.py settle >> prematch.log 2>&1
48:#PAUSED-543 * * * * * /root/pe-pg/keepalive.sh
49:#PAUSED-543 50 19,20 * * * [ "$(TZ=Europe/London date +\%H)" = "19" ] && cd /root/pe-report && python3 pg_report.py >> report.log 2>&1
52:#PAUSED-543 0 17 * * 5 cd /root/pe-report && python3 weekend_card.py >> weekend_card.log 2>&1
54:#PAUSED-543 * * * * * /root/pe-push/m1_keepalive.sh
55:#PAUSED-543 30 23 * * * cd /root/pe-report && python3 cleared_sync.py >> cleared_sync.log 2>&1
56:#PAUSED-543 30 4 * * * cd /root/pe-report && python3 retention.py >> retention.log 2>&1
57:#PAUSED-543 0 3 * * * cd /root/pe-cs && python3 qgreen_paper.py >> qgreen.log 2>&1
58:#PAUSED-543 55 23 * * * cd /root/pe-autopsy && python3 autopsy.py >> autopsy.log 2>&1
59:#PAUSED-543 @reboot sleep 120 && /root/pe-factory/resume.sh
60:#PAUSED-543 30 3 * * * /root/pe-factory/resume.sh
61:#PAUSED-543 0 */2 * * * /root/pe-factory/resume.sh
63:#PAUSED-543 20 7 * * * cd /root/pe-report && python3 morning.py >> morning.log 2>&1
64:#PAUSED-543 * * * * * /root/pe-race/keepalive.sh
65:#PAUSED-543 35 4 * * * cd /root/pe-race && python3 retention.py >> race.log 2>&1
66:#PAUSED-543 15 5 * * * cd /root/pe-factory && python3 copy_pros.py >> copy_pros.log 2>&1
67:#PAUSED-543 * * * * * /root/pe-clv/keepalive.sh
68:#PAUSED-543 40 5 * * * cd /root/pe-clv && python3 settle.py >> clv.log 2>&1
69:#PAUSED-543 10 3 * * * cd /root/pe-cs && python3 cs_late_paper.py >> cs_late_paper.log 2>&1
70:#PAUSED-543 * * * * * /root/pe-stats/keepalive.sh
71:#PAUSED-543 40 3 * * * cd /root/pe-factory && python3 inplay_factory.py >> inplay_factory.log 2>&1
72:#PAUSED-543 * * * * * /root/pe-tennis2/keepalive.sh
73:#PAUSED-543 50 5 * * * cd /root/pe-tennis2 && python3 settle.py >> dog.log 2>&1
74:#PAUSED-543 * * * * * /root/pe-cricket/keepalive.sh
75:#PAUSED-543 55 5 * * * cd /root/pe-cricket && python3 settle.py >> cricket.log 2>&1
76:#PAUSED-543 45 4 * * * cd /root/pe-cricket && python3 -c "import sys,psycopg2;sys.path.insert(0,'/root/pe-bot');from bot_core import DB;c=psycopg2.connect(DB,sslmode='require');c.autocommit=True;c.cursor().execute(\"DELETE FROM cricket_fav_tape WHERE ts<now()-interval '14 days'\")" >> cricket.log 2>&1
79:#PAUSED-543 * * * * * /root/pe-race/keepalive_mm.sh
80:#PAUSED-543 58 5 * * * cd /root/pe-factory && python3 robustness.py >> robustness.log 2>&1
81:#PAUSED-543 20 3 * * * cd /root/pe-cs && python3 stats_join.py >> stats_join.log 2>&1
82:#PAUSED-543 * * * * * /root/pe-ltd/keepalive.sh
83:#PAUSED-543 * * * * * /root/pe-ltd/keepalive_live.sh
84:#PAUSED-543 * * * * * /root/pe-stats/keepalive_espn.sh
85:#PAUSED-543 * * * * * /root/pe-xg/keepalive.sh
86:#PAUSED-543 * * * * * /root/pe-xg/keepalive_lo.sh
87:#PAUSED-543 * * * * * /root/pe-xg/keepalive_lo_live.sh
89:#PAUSED-543 * * * * * /root/pe-race/keepalive_mm_stream.sh
90:#PAUSED-543 40 4 * * * cd /root/pe-factory && python3 opp_map.py 3 >> opp_map.log 2>&1
91:#PAUSED-543 45 6 * * * cd /root/pe-push && python3 digest.py >> digest.log 2>&1
92:#PAUSED-543 * * * * * /root/pe-xg/keepalive_s9.sh
93:#PAUSED-543 30 3 * * * /root/pe-factory/retention.sh >> /root/pe-factory/retention.log 2>&1
97:#PAUSED-543 35 5 * * * cd /root/pe-factory && python3 t2_nightly.py >> t2.log 2>&1
98:#PAUSED-543 30 6,9,11,13,15,17,19,21,23 * * * python3 /root/pe-push/integrity.py --push >> /root/pe-push/integrity.log 2>&1
101:#PAUSED-543 * * * * * /root/pe-race/keepalive_mm_size.sh
102:#PAUSED-543 50 3 * * * python3 /root/pe-race/mm_kpis.py > /root/pe-race/mm_kpis.txt 2>&1
103:#PAUSED-543 40 6 * * * python3 /root/pe-push/shelf_daily.py >> /root/pe-push/shelf_daily.log 2>&1
107:#PAUSED-543 35 23 * * * cd /root/pe-coach && python3 coach_tape.py >> /root/pe-coach/coach.log 2>&1
115:#PAUSED-543 @reboot nohup /root/pe-player/keepalive_player.sh >/dev/null 2>&1 &
116:#PAUSED-543 */10 * * * * pgrep -f keepalive_player.sh >/dev/null || nohup /root/pe-player/keepalive_player.sh >/dev/null 2>&1 &
117:#PAUSED-543 40 6 * * * cd /root/pe-data && python3 paper_ledger.py >> ledger.log 2>&1
122:#PAUSED-543 20 */3 * * * python3 /root/pe-data/af_daily.py >> /root/pe-data/af_daily.log 2>&1
--- how mon/ht are counted
385:def write_brain_heartbeat(live_total, monitored_live, ht_total, notes=None):
391:                        (service_name, pulsed_at, live_fixtures, monitored_fixtures,
392:                         ht_fixtures, fires_this_session, notes)
394:                """, (SERVICE_NAME, live_total, monitored_live, ht_total,
665:        monitored = [f for f in all_fix if f.get('league', {}).get('id') in MONITORED_LEAGUES]
666:        return monitored, all_fix
675:def get_prematch_home_price(fixture_id):
721:    home_price = get_prematch_home_price(fixture_id) if needs_home_fav else None
857:def format_heartbeat(live_total, monitored_live, ht_total, strategies_count, open_trades=0):
859:            f"Live: {live_total} | Monitored: <b>{monitored_live}</b> | At HT: {ht_total}\n"
869:def maybe_send_heartbeat(monitored, all_fixtures, strategies, open_trades=0):
872:        ht_count = sum(1 for f in monitored if is_at_halftime(f))
873:        send_telegram(format_heartbeat(len(all_fixtures), len(monitored), ht_count,
912:    monitored, all_fix = get_live_fixtures()
913:    ht_fixtures = [f for f in monitored if is_at_halftime(f)]
924:    print(f"[{now_str}] live={len(all_fix)} mon={len(monitored)} ht={len(ht_fixtures)} "
936:    write_brain_heartbeat(len(all_fix), len(monitored), len(ht_fixtures), notes=notes[:500])
937:    maybe_send_heartbeat(monitored, all_fix, strategies, open_trades=open_trades_count)
940:    for fix in ht_fixtures:
function at 
--- the 25 Oct - 7 Nov alerts: stakes and real prices
   ('S28_HT_0_0_GOALHEAVY_U35', 38, Decimal('50.0000000000000000'), Decimal('452.980000000000132'), 5, 35)
   ('S24_HT_2_0_BACK_O25', 30, Decimal('50.0000000000000000'), Decimal('150.880000000000154'), 1, 23)
   ('L2_HT_0_0_DEFENSIVE_U25', 20, Decimal('50.0000000000000000'), Decimal('300.779999999999932'), 2, 19)
   ('S22_HT_4PLUS_NEXTGOAL', 18, Decimal('50.0000000000000000'), Decimal('202.499999999999944'), 0, 14)
   ('S21_HT_GOALFEST_O35', 17, Decimal('50.0000000000000000'), Decimal('16.249999999999956'), 0, 11)
   ('S25_HT_0_2_BACK_O25', 15, Decimal('50.0000000000000000'), Decimal('27.980000000000063'), 2, 11)
   ('S14B_HT_1_1_HIGH_SCORE_LEAGUE', 15, Decimal('50.0000000000000000'), Decimal('273.749999999999948'), 5, 13)
   ('S26_HT_3_0_BACK_O35', 11, Decimal('50.0000000000000000'), Decimal('237.499999999999960'), 3, 10)
   ('S19_HT_1_0_HOME_LEAD_O25', 7, Decimal('50.0000000000000000'), Decimal('-62.11999999999998'), 2, 3)
   ('S14_HT_1_1_HOME_FAV_O25', 5, Decimal('50.0000000000000000'), Decimal('123.819999999999984'), 1, 5)
   ('S27_HT_0_3_BACK_O35', 4, Decimal('50.0000000000000000'), Decimal('-42.500000000000008'), 1, 2)
   ('S6_HT_0_1_HOME_FAV_COMEBACK', 1, Decimal('50.0000000000000000'), Decimal('53.75000000000001'), 0, 1)
   ('BACK Under 2.5 Goals', 45, '0-0', Decimal('50.0'), Decimal('1.21'), 'WIN', Decimal('9.8'))
   ('BACK Over 2.5 Goals', 45, '1-0', Decimal('50.0'), Decimal('2.26'), 'LOSS', Decimal('-50.0'))
   ('BACK Under 2.5 Goals', 45, '0-0', Decimal('50.0'), None, 'WIN', Decimal('19.999999999999996'))
   ('BACK Over 2.5 Goals', 45, '2-0', Decimal('50.0'), None, 'WIN', Decimal('22.500000000000007'))
   ('BACK Under 2.5 Goals', 45, '0-0', Decimal('50.0'), None, 'LOSS', Decimal('-50.0'))
   ('BACK Over 2.5 Goals', 45, '1-0', Decimal('50.0'), Decimal('1.63'), 'WIN', Decimal('30.38'))
```
