#!/bin/bash
# 533: fallback for 527 stage 4. The Windows Python *installer* is known to hang under Wine; if 527 didn't leave a working
# MetaTrader5 import, install the EMBEDDABLE Python zip instead (no installer: unzip, enable site-packages, get-pip, pip install
# MetaTrader5) at the same path the bridge expects, then retry stage 5 (terminal attach). Idempotent: exits at once if the import
# already works. Appends to scoreboard/mt5_setup.txt.
LOG=/root/pe-fin/team/public/mt5_setup.txt
say(){ echo "$(date -u +%H:%M:%S) $*" | tee -a $LOG; }
export WINEPREFIX=/root/.mt5wine WINEARCH=win64 WINEDEBUG=-all DISPLAY=:99
pgrep -f "Xvfb :99" >/dev/null || (Xvfb :99 -screen 0 1280x1024x24 >/dev/null 2>&1 &); sleep 2
PYDIR="$WINEPREFIX/drive_c/Program Files/Python310"; PY="$PYDIR/python.exe"
ok(){ [ -f "$PY" ] && timeout 120 wine "$PY" -c "import MetaTrader5 as m; print('MT5PKG', m.__version__)" 2>/dev/null | grep -q MT5PKG; }
# give 527 time to finish if it is still inside its installer timeouts
for i in $(seq 1 40); do pgrep -f "py310.exe|pip install" >/dev/null || break; sleep 30; done
if ok; then say "533: MetaTrader5 package already importable — fallback not needed"; else
  say "533 stage 4b: embeddable Python fallback"
  pkill -f py310.exe 2>/dev/null; wineserver -k 2>/dev/null; sleep 3
  pgrep -f "Xvfb :99" >/dev/null || (Xvfb :99 -screen 0 1280x1024x24 >/dev/null 2>&1 &); sleep 2
  mkdir -p /root/pe-fin/mt5 && cd /root/pe-fin/mt5 || exit 1
  curl -sSL -o pyembed.zip https://www.python.org/ftp/python/3.10.11/python-3.10.11-embed-amd64.zip || { say "FAIL: embed zip download"; exit 1; }
  rm -rf "$PYDIR"; mkdir -p "$PYDIR"; python3 -c "import zipfile; zipfile.ZipFile('pyembed.zip').extractall('$PYDIR')" || { say "FAIL: unzip"; exit 1; }
  sed -i 's/^#import site/import site/' "$PYDIR"/python310._pth; grep -q '^Lib\\site-packages' "$PYDIR"/python310._pth || echo 'Lib\site-packages' >> "$PYDIR"/python310._pth
  curl -sSL -o "$PYDIR/get-pip.py" https://bootstrap.pypa.io/get-pip.py || { say "FAIL: get-pip download"; exit 1; }
  timeout 900 wine "$PY" "$PYDIR/get-pip.py" --no-warn-script-location >/dev/null 2>&1
  timeout 900 wine "$PY" -m pip install -q --no-warn-script-location MetaTrader5 >/dev/null 2>&1
  ok && say "PASS stage 4b: $(timeout 120 wine "$PY" -c 'import MetaTrader5 as m; print(m.__version__)' 2>/dev/null | tail -1 | tr -d '\r')" || { say "FAIL stage 4b: MetaTrader5 still not importable"; /root/pe-fin/team/publish.sh >/dev/null 2>&1; exit 1; }
fi
if [ ! -f /root/pe-fin/mt5/run_terminal.sh ]; then cat > /root/pe-fin/mt5/run_terminal.sh <<'SH'
#!/bin/bash
export WINEPREFIX=/root/.mt5wine WINEARCH=win64 WINEDEBUG=-all DISPLAY=:99
pgrep -f "Xvfb :99" >/dev/null || (Xvfb :99 -screen 0 1280x1024x24 >/dev/null 2>&1 &)
sleep 2; pgrep -f terminal64.exe >/dev/null || (wine "$WINEPREFIX/drive_c/Program Files/MetaTrader 5/terminal64.exe" /portable >/dev/null 2>&1 &)
SH
chmod +x /root/pe-fin/mt5/run_terminal.sh; ( crontab -l 2>/dev/null | grep -v run_terminal.sh; echo "@reboot /root/pe-fin/mt5/run_terminal.sh"; echo "*/10 * * * * /root/pe-fin/mt5/run_terminal.sh" ) | crontab -; fi
say "stage 5 (retry): terminal + attach (no account yet)"
/root/pe-fin/mt5/run_terminal.sh 2>/dev/null || (wine "$WINEPREFIX/drive_c/Program Files/MetaTrader 5/terminal64.exe" /portable >/dev/null 2>&1 &)
sleep 60
OUT=$(timeout 120 wine "$PY" -c "import MetaTrader5 as m; ok=m.initialize(); print('INIT',ok,m.last_error()); print('VERSION',m.version()); m.shutdown()" 2>/dev/null | tr -d '\r')
say "$OUT"
echo "$OUT" | grep -q "VERSION (" && say "PASS stage 5: terminal running and Python attached" || say "STAGE 5 NOT YET: attach may need the demo login — re-checked automatically when the login lands"
say "DONE 533"
/root/pe-fin/team/publish.sh >/dev/null 2>&1; echo published
