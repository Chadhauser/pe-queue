# Restart collectors — 2026-11-16 17:10 UTC

## bookie_v2 processes
      13261 Mon Nov 16 16:05:52 2026 /bin/bash /root/pe-sports/bookie/run_bookie_v2.sh
      13262 Mon Nov 16 16:05:52 2026 python3 bookie_v2.py

## Where each collector is started
### ip_tape
### liq_sample
### xx_tape
### monitor_ht
    cron: */5 * * * * pgrep -f 'brain/monitor_ht.py' >/dev/null || nohup /root/pe-brain/run_monitor_ht.sh >/dev/null 2>&1 &
    script: /root/pe-fin/team/repo/jobs/561_ceo_13nov_freeze_goalsignal_friday_email.sh
    script: /root/pe-fin/team/repo/jobs/540_brain_services_to_contabo.sh
    script: /root/pe-finq/repo/jobs/561_ceo_13nov_freeze_goalsignal_friday_email.sh
### espn
    script: /root/pe-fin/team/repo/jobs/202_espn_stats_recorder_and_xg_targeting.sh
    script: /root/pe-finq/repo/jobs/202_espn_stats_recorder_and_xg_targeting.sh
    script: /root/pe-queue/jobs/202_espn_stats_recorder_and_xg_targeting.sh
### xg_
    script: /root/pe-fin/team/repo/jobs/267_xg_exit_fallthrough_and_audit_tweaks.sh
    script: /root/pe-fin/team/repo/jobs/255_xg_paper_settle_fix.sh
    script: /root/pe-fin/team/repo/jobs/209_xg_paper_bot_and_ltd_verdict.sh
### brain
    cron: */5 * * * * pgrep -f 'brain/monitor_ht.py' >/dev/null || nohup /root/pe-brain/run_monitor_ht.sh >/dev/null 2>&1 &
    cron: */5 * * * * pgrep -f 'brain/stats_collector.py' >/dev/null || nohup /root/pe-brain/run_stats_collector.sh >/dev/null 2>&1 &
    script: /root/pe-fin/team/repo/jobs/561_ceo_13nov_freeze_goalsignal_friday_email.sh
    script: /root/pe-fin/team/repo/jobs/540_brain_services_to_contabo.sh
    script: /root/pe-finq/repo/jobs/561_ceo_13nov_freeze_goalsignal_friday_email.sh
### goal_monitor
### goal_signal
### stream_client
    script: /root/pe-fin/team/repo/jobs/252_stream_client_book_fix.sh
    script: /root/pe-fin/team/repo/jobs/290_stream_dead_connection_fix.sh
    script: /root/pe-fin/team/repo/jobs/281_stream_tennis_footpre_books.sh
### sports_team
    cron: */10 * * * * pgrep -f 'sports_team.py' >/dev/null || nohup /root/pe-sports/team/run_team.sh &
    script: /root/pe-fin/team/repo/jobs/510_sports_team_daemon.sh
    script: /root/pe-fin/team/repo/jobs/511_data_health_fixes.sh
    script: /root/pe-fin/team/repo/jobs/518_fade_exits_bookie_line.sh

## Watchdog / keepalive scripts in cron
    */5 * * * * cd /root/pe-logger && /usr/bin/python3 watchdog.py >> watchdog.log 2>&1
    * * * * * /root/pe-liq/keepalive.sh
    * * * * * /root/pe-ip/keepalive.sh
    * * * * * /root/pe-xx/keepalive.sh
    * * * * * /root/pe-stream/keepalive.sh
    0 8 * * * cd /root/pe-fin && python3 fin_watchdog.py >> fin_watchdog.log 2>&1
    */5 * * * * python3 /root/pe-push/watchdog.py >> /root/pe-push/watchdog.log 2>&1
    @reboot nohup /root/pe-hist/keepalive_hist.sh >/dev/null 2>&1 &
    */10 * * * * pgrep -f keepalive_hist.sh >/dev/null || nohup /root/pe-hist/keepalive_hist.sh >/dev/null 2>&1 &
    20 * * * * /root/pe-sports/team/break_check.sh >> /root/pe-sports/team/break_check.log 2>&1

## Running each watchdog once
- cd /root/pe-logger && /usr/bin/python3 watchdog.py >> watchdog.log 2>&1
  exit 0
- /root/pe-liq/keepalive.sh
  exit 0
- /root/pe-ip/keepalive.sh
  exit 0
- /root/pe-xx/keepalive.sh
  exit 0
- /root/pe-stream/keepalive.sh
  exit 0
- cd /root/pe-fin && python3 fin_watchdog.py >> fin_watchdog.log 2>&1
  exit 0
- python3 /root/pe-push/watchdog.py >> /root/pe-push/watchdog.log 2>&1
  exit 0
- &
  exit 2
- pgrep -f keepalive_hist.sh >/dev/null || nohup /root/pe-hist/keepalive_hist.sh >/dev/null 2>&1 &
  exit 0

## Process counts now
- stream_client: 1
- ip_tape: 0
- liq_sample: 0
- xx_tape: 0
- bookie_v2: 2
- monitor_ht: 0
- sports_team: 1
- espn: 0
- xg: 0
- brain: 0
- goal: 0
- late_over: 0
- lo_live: 0

## In-play engine error (615)
file: /root/pe-sports/team/fairprice_inplay.py
    Traceback (most recent call last):
      File "/root/pe-sports/team/fairprice_inplay.py", line 32, in <module>
        cur.execute("SELECT market_type, count(DISTINCT market_id) FROM bf_hist_other WHERE sport='Soccer' GROUP BY 1 ORDER BY 2 DESC"); types=cur.fetchall(); print("types:",types,flush=True)
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    psycopg2.OperationalError: server closed the connection unexpectedly
    	This probably means the server terminated abnormally
    	before or while processing the request.
    
