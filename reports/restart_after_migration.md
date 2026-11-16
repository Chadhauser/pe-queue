# Restart after migration — 2026-11-16 16:47 UTC

free -g: 17 GB total, 14 GB available | nproc 6 | disk free  824G

## Services (systemd) matching our names
      lvm2-monitor.service                           loaded    active   exited  Monitoring of LVM2 mirrors, snapshots etc. using dmeventd or progress polling

## @reboot cron lines
    #PAUSED-543 @reboot cd ~/pe-logger && nohup python3 server_price_logger.py >> logger.log 2>&1 &
    #PAUSED-543 @reboot cd ~/pe-logger && nohup python3 racing_price_logger.py >> racing.log 2>&1 &
    #PAUSED-543 @reboot cd ~/pe-logger && nohup python3 tennis_price_logger.py >> tennis.log 2>&1 &
    #PAUSED-543 @reboot cd /root/pe-logger && nohup python3 golf_price_logger.py >> golf.log 2>&1 &
    #PAUSED-543 @reboot cd /root/pe-push && nohup python3 send_push.py >> push.log 2>&1 &
    #PAUSED-543 @reboot cd /root/pe-bot && nohup python3 trade_bot.py >> bot.log 2>&1 &
    #PAUSED-543 @reboot cd /root/pe-tennis && nohup python3 tennis_bot.py >> tennis.log 2>&1 &
    #PAUSED-543 @reboot sleep 120 && /root/pe-factory/resume.sh
    @reboot cd /root/pe-fin && nohup ./duka_loop.sh > /dev/null 2>&1 &
    @reboot nohup /root/pe-hist/keepalive_hist.sh >/dev/null 2>&1 &
    #PAUSED-543 @reboot nohup /root/pe-player/keepalive_player.sh >/dev/null 2>&1 &
    @reboot nohup /root/pe-sports/team/run_team.sh &

## Actions
- @reboot golf_price_logger.py: was not running, started: NO
- @reboot send_push.py: was not running, started: NO
- @reboot trade_bot.py: was not running, started: NO
- @reboot tennis_bot.py: was not running, started: NO

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

REAL_MONEY_OFF present: yes
