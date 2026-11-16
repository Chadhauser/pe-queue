#!/bin/bash
# 541: PETER 16 Nov 14:33: "stop this all, it has messed up my sports trading". Stop EVERY financial-trading process and cron on
# this box (MT5/Wine, team loop, data pulls, paper bots), flatten the Alpaca PAPER account, free apt cache. Nothing deleted;
# all pausable code stays on disk. Sports crons untouched (only lines containing /root/pe-fin/ or mt5 are removed). Backup of the
# crontab first. Nothing financial restarts until Peter says so.
crontab -l > /root/crontab_before_fin_stop_$(date +%Y%m%d%H%M).txt
pkill -f 540_fin_mt5; pkill -f mt5_bridge.py; pkill -f terminal64.exe; WINEPREFIX=/root/.mt5wine wineserver -k 2>/dev/null
pkill -f run_team.sh; pkill -f fin_team.py; pkill -f duka_loop.sh; pkill -f orb_alpaca_bot.py; pkill -f k2_gapfade_bot.py; pkill -f k4_reversal_bot.py
( crontab -l | grep -v -E '/root/pe-fin/|mt5' ) | crontab -
python3 - <<'PY'
import sys,requests; sys.path.insert(0,'/root/pe-queue/runner'); import creds; E=creds.all_vars()
H={'APCA-API-KEY-ID':E['ALPACA_KEY'],'APCA-API-SECRET-KEY':E['ALPACA_SECRET']}; T='https://paper-api.alpaca.markets/v2'
print('cancel orders',requests.delete(T+'/orders',headers=H,timeout=30).status_code,'| close paper positions',requests.delete(T+'/positions',headers=H,timeout=30).status_code)
PY
apt-get clean
echo "remaining fin processes:"; pgrep -af "pe-fin|mt5|terminal64|wine" | grep -v pgrep
echo "fin cron lines left: $(crontab -l | grep -cE '/root/pe-fin/|mt5')"; df -h / | tail -1
du -sh /root/.mt5wine /root/pe-data /root/pe-fin 2>/dev/null
echo "DONE 541 — financial work stopped"
