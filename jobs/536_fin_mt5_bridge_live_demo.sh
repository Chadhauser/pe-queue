#!/bin/bash
# 536: Peter's test 16 Nov 13:56 proved the fix — with OPENBLAS_NUM_THREADS=1, numpy 2.0.2 + MetaTrader5 5.0.6231 import cleanly
# under Wine (without it numpy's thread start-up hangs). Bake that into every Wine launcher, let the bridge start the terminal
# itself (initialize with path=terminal64.exe), log into the Darwinex DEMO (login/server/password from /root/pe-logger/.env),
# and write the result to scoreboard/mt5_setup.txt: account number, demo flag, equity, and the Nasdaq-100 symbol(s) on offer.
LOG=/root/pe-fin/team/public/mt5_setup.txt
say(){ echo "$(date -u +%H:%M:%S) $*" | tee -a $LOG; }
cd /root/pe-fin/mt5 || exit 1
for f in run_terminal.sh run_bridge.sh; do
  [ -f $f ] && { grep -q OPENBLAS_NUM_THREADS $f || sed -i 's/^export WINEPREFIX=/export OPENBLAS_NUM_THREADS=1 WINEPREFIX=/' $f; }
done
grep -q "path=E.get('MT5_TERMINAL'" mt5_bridge.py || sed -i "s|ok=mt5.initialize(login=|ok=mt5.initialize(path=E.get('MT5_TERMINAL','C:/Program Files/MetaTrader 5/terminal64.exe'),timeout=120000,login=|" mt5_bridge.py
grep -c "path=E.get('MT5_TERMINAL'" mt5_bridge.py | sed 's/^/initialize-with-path patched: /'
export OPENBLAS_NUM_THREADS=1 WINEPREFIX=/root/.mt5wine WINEARCH=win64 WINEDEBUG=-all DISPLAY=:99
pkill -f mt5_bridge.py; WINEPREFIX=/root/.mt5wine wineserver -k; sleep 3
pgrep -f "Xvfb :99" >/dev/null || (Xvfb :99 -screen 0 1280x1024x24 >/dev/null 2>&1 &); sleep 2
grep -q '^MT5_LOGIN=' /root/pe-logger/.env && say "536: MT5 login found on the box (demo)" || { say "536: no MT5_LOGIN on the box"; exit 1; }
: > bridge.log
(wine "$WINEPREFIX/drive_c/Program Files/Python310/python.exe" Z:/root/pe-fin/mt5/mt5_bridge.py </dev/null >/dev/null 2>&1 &)
for i in $(seq 1 30); do grep -qE "connected|REFUSING|failed" bridge.log 2>/dev/null && break; sleep 10; done
say "bridge: $(tail -3 bridge.log | tr '\n' ' ')"
sleep 10
if [ -f heartbeat.json ]; then
  say "heartbeat: $(python3 -c "import json;h=json.load(open('heartbeat.json'));print('login',h['login'],'demo',h['demo'],'equity',h['equity'],h['currency'],'positions',len(h['positions']))")"
  cp /root/pe-fin/mt5/mt5_client.py /root/pe-fin/team/mt5_client.py 2>/dev/null
  cd /root/pe-fin/team && python3 - <<'PY' | tee -a /root/pe-fin/team/public/mt5_setup.txt
import mt5_client as B
for pat in ('*NDX*','*US100*','*USTEC*','*NAS*','*SP500*','*SPX*'):
    r=B.call(dict(action='symbols',pattern=pat),timeout=40)
    if r.get('ok') and r.get('symbols'): print(f"symbols {pat}: "+', '.join(f"{s['name']} (min {s['vol_min']} step {s['vol_step']} tick {s['tick_size']} = {s['tick_value']})" for s in r['symbols'][:5]))
q=B.call(dict(action='quote',symbol='NDX'),timeout=30); print('quote NDX:',q)
PY
  say "PASS: bridge live on the Darwinex DEMO"
else say "NOT YET: no heartbeat — see bridge log above"; fi
( crontab -l 2>/dev/null | grep -v run_bridge.sh; echo "*/5 * * * * /root/pe-fin/mt5/run_bridge.sh" ) | crontab -
say "DONE 536"; /root/pe-fin/team/publish.sh >/dev/null 2>&1; echo published
