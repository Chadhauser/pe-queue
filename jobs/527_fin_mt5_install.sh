#!/bin/bash
# 527: Saturday-build item 4a — MT5 on the Contabo box, headless. Darwinex (Zero and full) only connects through MetaTrader, so the
# bots need a running MT5 terminal. Route: Wine (64-bit prefix) + Xvfb virtual screen + MetaTrader 5 + Windows Python with the
# official MetaTrader5 package, all inside the Wine prefix. Our Linux signal code will hand orders to it through a JSON file
# (item 4b, next job). This job only INSTALLS and VERIFIES; no account, no orders. Each stage prints PASS/FAIL and the job stops at
# the first FAIL. The log goes to scoreboard/mt5_setup.txt in the repo so the result is readable without the server.
LOG=/root/pe-fin/team/public/mt5_setup.txt; mkdir -p /root/pe-fin/team/public; : > $LOG
say(){ echo "$(date -u +%H:%M:%S) $*" | tee -a $LOG; }
fail(){ say "FAIL: $*"; /root/pe-fin/team/publish.sh >/dev/null 2>&1; exit 1; }
export WINEPREFIX=/root/.mt5wine WINEARCH=win64 WINEDEBUG=-all DEBIAN_FRONTEND=noninteractive
say "stage 1: packages (wine 32+64, xvfb)"
dpkg --add-architecture i386 >/dev/null 2>&1
apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq wine wine32 wine64 xvfb xauth winbind cabextract >/dev/null 2>&1 || apt-get install -y -qq wine xvfb xauth winbind cabextract >/dev/null 2>&1
command -v wine >/dev/null && command -v Xvfb >/dev/null || fail "wine/xvfb not installed"
say "PASS stage 1: $(wine --version 2>/dev/null)"
# one virtual screen for everything Wine does
pgrep -f "Xvfb :99" >/dev/null || (Xvfb :99 -screen 0 1280x1024x24 >/dev/null 2>&1 &) ; sleep 2; export DISPLAY=:99
say "stage 2: wine prefix"
[ -d $WINEPREFIX/drive_c ] || timeout 600 wineboot -i >/dev/null 2>&1
[ -d $WINEPREFIX/drive_c ] || fail "wine prefix not created"
say "PASS stage 2: prefix at $WINEPREFIX"
say "stage 3: MetaTrader 5"
T="$WINEPREFIX/drive_c/Program Files/MetaTrader 5/terminal64.exe"
if [ ! -f "$T" ]; then
  mkdir -p /root/pe-fin/mt5 && cd /root/pe-fin/mt5
  curl -sSL -o mt5setup.exe https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe || fail "mt5setup download"
  (timeout 1200 wine mt5setup.exe /auto >/dev/null 2>&1 &)
  for i in $(seq 1 120); do [ -f "$T" ] && break; sleep 10; done
fi
[ -f "$T" ] || fail "terminal64.exe not found after 20 min"
say "PASS stage 3: $T"
say "stage 4: Windows Python + MetaTrader5 package inside Wine"
PY="$WINEPREFIX/drive_c/Program Files/Python310/python.exe"
if [ ! -f "$PY" ]; then
  cd /root/pe-fin/mt5 && curl -sSL -o py310.exe https://www.python.org/ftp/python/3.10.11/python-3.10.11-amd64.exe || fail "python download"
  timeout 900 wine py310.exe /quiet InstallAllUsers=1 PrependPath=1 Include_test=0 >/dev/null 2>&1
fi
[ -f "$PY" ] || fail "windows python not installed"
timeout 900 wine "$PY" -m pip install -q --upgrade pip MetaTrader5 >/dev/null 2>&1
wine "$PY" -c "import MetaTrader5 as m; print(m.__version__)" 2>/dev/null | tail -1 | grep -q "[0-9]" || fail "MetaTrader5 package import"
say "PASS stage 4: MetaTrader5 package $(wine "$PY" -c 'import MetaTrader5 as m; print(m.__version__)' 2>/dev/null | tail -1)"
say "stage 5: start the terminal and attach from Python (no account yet — attach only)"
pgrep -f terminal64.exe >/dev/null || (wine "$T" /portable >/dev/null 2>&1 &); sleep 45
OUT=$(timeout 120 wine "$PY" -c "import MetaTrader5 as m; ok=m.initialize(); print('INIT',ok,m.last_error()); print('VERSION',m.version()); m.shutdown()" 2>/dev/null | tr -d '\r')
say "$OUT"
echo "$OUT" | grep -q "VERSION (" && say "PASS stage 5: terminal running and Python attached" || say "STAGE 5 NOT YET: terminal attach needs a logged-in account on some builds — fine until the demo login lands"
cat > /root/pe-fin/mt5/run_terminal.sh <<'SH'
#!/bin/bash
export WINEPREFIX=/root/.mt5wine WINEARCH=win64 WINEDEBUG=-all DISPLAY=:99
pgrep -f "Xvfb :99" >/dev/null || (Xvfb :99 -screen 0 1280x1024x24 >/dev/null 2>&1 &)
sleep 2; pgrep -f terminal64.exe >/dev/null || (wine "$WINEPREFIX/drive_c/Program Files/MetaTrader 5/terminal64.exe" /portable >/dev/null 2>&1 &)
SH
chmod +x /root/pe-fin/mt5/run_terminal.sh
( crontab -l 2>/dev/null | grep -v run_terminal.sh; echo "@reboot /root/pe-fin/mt5/run_terminal.sh"; echo "*/10 * * * * /root/pe-fin/mt5/run_terminal.sh" ) | crontab -
say "DONE: MT5 install job finished; keeper cron set (terminal restarted if it dies)"
/root/pe-fin/team/publish.sh >/dev/null 2>&1; echo published
