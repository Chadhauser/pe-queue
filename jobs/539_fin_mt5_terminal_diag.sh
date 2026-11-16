#!/bin/bash
# 539: diagnose why the MT5 terminal never answers Python (538: terminal log empty, pipe timeout). Read-only apart from
# restarting the terminal: is terminal64.exe alive, which log files did it write and what do they say, what is on the virtual
# screen (screenshot -> scoreboard/mt5_screen.png), and what Wine prints when the terminal starts. Output -> scoreboard/mt5_diag.txt
P=/root/pe-fin/team/public; O=$P/mt5_diag.txt; : > $O
export OPENBLAS_NUM_THREADS=1 WINEPREFIX=/root/.mt5wine WINEARCH=win64 DISPLAY=:99
TD="$WINEPREFIX/drive_c/Program Files/MetaTrader 5"
{
echo "== 539 $(date -u +%FT%H:%M) | wine $(wine --version)"
echo "== processes"; ps -eo pid,etime,rss,cmd | grep -iE "terminal64|wineserver|python.exe|Xvfb" | grep -v grep
echo "== install dir"; ls -la "$TD" | head -40
echo "== log files touched in last 3h"; find "$WINEPREFIX/drive_c" -name "*.log" -mmin -180 2>/dev/null | head -20
for f in $(find "$WINEPREFIX/drive_c" -name "*.log" -mmin -180 2>/dev/null | head -6 | tr ' ' '?'); do echo "--- $f"; iconv -f UTF-16LE -t UTF-8 "$f" 2>/dev/null | tr -d '\r' | tail -15 | cut -c1-200; done
command -v import >/dev/null || apt-get install -y -qq imagemagick >/dev/null 2>&1
import -window root $P/mt5_screen.png 2>&1 | head -2 && echo "screenshot 1 saved"
echo "== restart terminal in foreground for 90s with Wine errors on"
pkill -f mt5_bridge.py; wineserver -k; sleep 3
pgrep -f "Xvfb :99" >/dev/null || (Xvfb :99 -screen 0 1280x1024x24 >/dev/null 2>&1 &); sleep 2
WINEDEBUG=err+all,fixme-all timeout 90 wine "$TD/terminal64.exe" /portable "/config:Z:\\root\\pe-fin\\mt5\\login.ini" > /root/pe-fin/mt5/term_fg.txt 2>&1
echo "exit $? ; wine output (last 40 lines, de-duplicated):"; sort /root/pe-fin/mt5/term_fg.txt | uniq -c | sort -rn | head -40 | cut -c1-220
import -window root $P/mt5_screen2.png 2>/dev/null; echo "screenshot 2 (taken after 90s) saved"
echo "== logs after foreground run"; for f in $(find "$WINEPREFIX/drive_c" -name "*.log" -mmin -5 2>/dev/null | head -6 | tr ' ' '?'); do echo "--- $f"; iconv -f UTF-16LE -t UTF-8 "$f" 2>/dev/null | tr -d '\r' | tail -20 | cut -c1-200; done
} >> $O 2>&1
# leave the terminal running in the background for the keeper
/root/pe-fin/mt5/run_terminal.sh
sed -i 's/Password=.*/Password=***/I' $O
echo "DONE 539" >> $O; /root/pe-fin/team/publish.sh >/dev/null 2>&1; echo published
