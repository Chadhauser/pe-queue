#!/bin/bash
# 535: diagnose why MetaTrader5 won't import in Wine's Python (527/533 hid the errors). Prints the real error lines to
# scoreboard/mt5_setup.txt, then tries the two common fixes: (a) install numpy first (MetaTrader5 needs numpy; pip under Wine can
# fail to resolve it), (b) vcrun2015-2022 runtime via winetricks-free download of the MS redistributable. Stops at the first PASS.
LOG=/root/pe-fin/team/public/mt5_setup.txt
say(){ echo "$(date -u +%H:%M:%S) $*" | tee -a $LOG; }
export WINEPREFIX=/root/.mt5wine WINEARCH=win64 WINEDEBUG=-all DISPLAY=:99
pgrep -f "Xvfb :99" >/dev/null || (Xvfb :99 -screen 0 1280x1024x24 >/dev/null 2>&1 &); sleep 2
PYDIR="$WINEPREFIX/drive_c/Program Files/Python310"; PY="$PYDIR/python.exe"
say "535 diag: python.exe present? $( [ -f "$PY" ] && echo yes || echo NO )"
say "python version: $(timeout 120 wine "$PY" -c 'import sys;print(sys.version)' 2>&1 | tail -2 | tr -d '\r' | tr '\n' ' ')"
say "pip version: $(timeout 120 wine "$PY" -m pip --version 2>&1 | tail -2 | tr -d '\r' | tr '\n' ' ')"
say "pip list: $(timeout 180 wine "$PY" -m pip list 2>&1 | tr -d '\r' | grep -iE 'numpy|metatrader' | tr '\n' ' ')"
say "import error: $(timeout 120 wine "$PY" -c 'import MetaTrader5' 2>&1 | tr -d '\r' | tail -4 | tr '\n' ' ')"
ok(){ timeout 120 wine "$PY" -c "import MetaTrader5 as m; print('MT5PKG', m.__version__)" 2>/dev/null | grep -q MT5PKG; }
say "fix (a): pip install numpy then MetaTrader5 (errors shown)"
say "numpy: $(timeout 900 wine "$PY" -m pip install --no-warn-script-location 'numpy<2.1' 2>&1 | tr -d '\r' | tail -3 | tr '\n' ' ')"
say "MetaTrader5: $(timeout 900 wine "$PY" -m pip install --no-warn-script-location MetaTrader5 2>&1 | tr -d '\r' | tail -3 | tr '\n' ' ')"
if ok; then say "PASS fix (a): $(timeout 120 wine "$PY" -c 'import MetaTrader5 as m; print(m.__version__)' 2>/dev/null | tail -1 | tr -d '\r')"; else
  say "fix (b): Microsoft VC++ runtime"
  cd /root/pe-fin/mt5 && curl -sSL -o vc_redist.x64.exe https://aka.ms/vs/17/release/vc_redist.x64.exe && timeout 900 wine vc_redist.x64.exe /install /quiet /norestart >/dev/null 2>&1
  say "import after VC++: $(timeout 120 wine "$PY" -c 'import MetaTrader5 as m; print(m.__version__)' 2>&1 | tr -d '\r' | tail -3 | tr '\n' ' ')"
  ok && say "PASS fix (b)" || say "STILL FAILING — error above; next door: run the bridge via MT5's own MQL5 file EA instead of the Python package"
fi
if ok; then
  /root/pe-fin/mt5/run_terminal.sh 2>/dev/null; sleep 60
  say "attach: $(timeout 120 wine "$PY" -c "import MetaTrader5 as m; ok=m.initialize(); print('INIT',ok,m.last_error()); print('VERSION',m.version()); m.shutdown()" 2>&1 | tr -d '\r' | tail -2 | tr '\n' ' ')"
  /root/pe-fin/mt5/run_bridge.sh; sleep 40; say "bridge log: $(tail -3 /root/pe-fin/mt5/bridge.log 2>/dev/null | tr '\n' ' ')"
fi
say "DONE 535"; /root/pe-fin/team/publish.sh >/dev/null 2>&1; echo published
