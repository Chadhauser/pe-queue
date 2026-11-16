#!/bin/bash
# 540: 539's screenshot shows the real blocker: the MT5 terminal stops at "A debugger has been found running in your system"
# (its copy protection misreads Ubuntu's Wine 9.0). Known MetaQuotes-forum fix: run it under WineHQ's wine-STAGING build.
# Steps: stop everything MT5, swap Ubuntu wine for WineHQ winehq-staging (same prefix, Python and terminal kept), switch off
# Wine's auto-debugger, start the terminal pre-logged-in, screenshot, and if it authorises start the bridge. Demo only.
P=/root/pe-fin/team/public; LOG=$P/mt5_setup.txt; say(){ echo "$(date -u +%H:%M:%S) $*" | tee -a $LOG; }
export DEBIAN_FRONTEND=noninteractive
( crontab -l 2>/dev/null | grep -v -e run_bridge.sh -e run_terminal.sh ) | crontab -
pkill -f mt5_bridge.py; WINEPREFIX=/root/.mt5wine wineserver -k 2>/dev/null; pkill -f terminal64.exe; pkill -f start.exe; sleep 3
say "540: swapping Ubuntu wine for WineHQ wine-staging"
CODE=$(. /etc/os-release; echo $VERSION_CODENAME)
mkdir -pm755 /etc/apt/keyrings
curl -fsSL -o /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key || { say "FAIL: winehq key download"; exit 1; }
curl -fsSL -o /etc/apt/sources.list.d/winehq-$CODE.sources https://dl.winehq.org/wine-builds/ubuntu/dists/$CODE/winehq-$CODE.sources || { say "FAIL: winehq sources for $CODE"; exit 1; }
dpkg --add-architecture i386; apt-get update -qq >/dev/null 2>&1
apt-get remove -y -qq wine wine64 wine32 libwine >/dev/null 2>&1
timeout 1800 apt-get install -y -qq --install-recommends winehq-staging >/tmp/winehq_install.txt 2>&1 || { say "FAIL: winehq-staging install: $(tail -3 /tmp/winehq_install.txt | tr '\n' ' ')"; }
hash -r; say "wine now: $(wine --version 2>&1) at $(command -v wine)"
export OPENBLAS_NUM_THREADS=1 WINEPREFIX=/root/.mt5wine WINEARCH=win64 WINEDEBUG=-all DISPLAY=:99
pgrep -f "Xvfb :99" >/dev/null || (Xvfb :99 -screen 0 1280x1024x24 >/dev/null 2>&1 &); sleep 2
timeout 600 wineboot -u >/dev/null 2>&1; say "prefix updated"
wine reg add "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion\\AeDebug" /v Auto /t REG_SZ /d 0 /f >/dev/null 2>&1
wine reg delete "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion\\AeDebug" /v Debugger /f >/dev/null 2>&1
say "python check: $(timeout 120 wine 'C:/Program Files/Python310/python.exe' -c 'import numpy,MetaTrader5 as m;print(numpy.__version__,m.__version__)' 2>/dev/null | tr -d '\r' | tail -1)"
TD="$WINEPREFIX/drive_c/Program Files/MetaTrader 5"
/root/pe-fin/mt5/run_terminal.sh
TL(){ f=$(ls -t "$TD"/logs/*.log 2>/dev/null | head -1); [ -n "$f" ] && iconv -f UTF-16LE -t UTF-8 "$f" 2>/dev/null | tr -d '\r'; }
for i in $(seq 1 30); do TL | grep -qiE "authoriz|synchroniz" && break; sleep 10; done
import -window root $P/mt5_screen3.png 2>/dev/null
say "terminal log: $(TL | grep -iE 'authoriz|synchroni|connect|login|invalid|fail|update' | tail -6 | cut -c1-160 | tr '\n' '|') (screenshot: scoreboard/mt5_screen3.png)"
cd /root/pe-fin/mt5 && : > bridge.log
(wine "$WINEPREFIX/drive_c/Program Files/Python310/python.exe" Z:/root/pe-fin/mt5/mt5_bridge.py </dev/null >/dev/null 2>&1 &)
for i in $(seq 1 30); do grep -qE "connected|REFUSING|failed" bridge.log 2>/dev/null && break; sleep 10; done
say "bridge: $(tail -3 bridge.log | tr '\n' ' ')"; sleep 10
if [ -f heartbeat.json ] && [ $(( $(date +%s) - $(stat -c %Y heartbeat.json) )) -lt 60 ]; then
  say "heartbeat: $(python3 -c "import json;h=json.load(open('heartbeat.json'));print('login',h['login'],'demo',h['demo'],'equity',h['equity'],h['currency'],'positions',len(h['positions']))")"
  cd /root/pe-fin/team && python3 - <<'PY' | tee -a /root/pe-fin/team/public/mt5_setup.txt
import mt5_client as B
for pat in ('*NDX*','*US100*','*USTEC*','*NAS*','*SP500*','*SPX*'):
    r=B.call(dict(action='symbols',pattern=pat),timeout=40)
    if r.get('ok') and r.get('symbols'): print(f"symbols {pat}: "+', '.join(f"{s['name']} (min {s['vol_min']} step {s['vol_step']} tick {s['tick_size']} = {s['tick_value']})" for s in r['symbols'][:5]))
print('quote NDX:',B.call(dict(action='quote',symbol='NDX'),timeout=30))
PY
  say "PASS: bridge live on the Darwinex DEMO"
else say "NOT YET: no fresh heartbeat"; fi
( crontab -l 2>/dev/null | grep -v -e run_bridge.sh -e run_terminal.sh; echo "@reboot /root/pe-fin/mt5/run_terminal.sh"; echo "*/5 * * * * /root/pe-fin/mt5/run_bridge.sh" ) | crontab -
say "DONE 540"; /root/pe-fin/team/publish.sh >/dev/null 2>&1; echo published
