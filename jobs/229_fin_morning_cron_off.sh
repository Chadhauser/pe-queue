#!/bin/bash
# 229: Peter does not want a daily financial report. Remove the 07:25 cron from job 228; keep /root/pe-report/fin_morning.py for on-demand runs.
( crontab -l 2>/dev/null | grep -v fin_morning.py ) | crontab -
crontab -l | grep -c fin_morning.py; echo "fin_morning cron removed (0 above = confirmed)"
