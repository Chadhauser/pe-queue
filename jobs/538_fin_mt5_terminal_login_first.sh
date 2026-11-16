#!/bin/bash
# 538: 536 got further — Python now reaches the terminal, but "Pipe server didn't answer in 60 sec": the terminal was still
# starting/logging in when Python asked. Fix: start the terminal OURSELVES first, already logged into the Darwinex DEMO via a
# startup config (login/server/password from /root/pe-logger/.env, file chmod 600, never in the repo), wait until the terminal's
# own log says it is authorised, THEN start the bridge (attach with portable=True). Terminal log lines go to mt5_setup.txt.
# Also writes the paper bots' state after 537 (patched? running? armed for today's open?) to scoreboard/bots_today.txt.
P=/root/pe-fin/team/public; LOG=$P/mt5_setup.txt; say(){ echo "$(date -u +%H:%M:%S) $*" | tee -a $LOG; }
B=$P/bots_today.txt; { echo "BOTS $(date -u +%FT%H:%M) UTC | NY $(TZ=America/New_York date +%H:%M)"; grep -c TRADING_DAY_CHECK /root/pe-fin/bot/orb_alpaca_bot.py /root/pe-fin/bot/k2_gapfade_bot.py; echo "running:"; pgrep -af "orb_alpaca_bot|k2_gapfade_bot|k4_reversal_bot" | grep -v pgrep; echo "--- orb log"; tail -4 /root/pe-fin/bot/orb_alpaca.log; echo "--- k2 log"; tail -4 /root/pe-fin/bot/k2.log 2>/dev/null; } > $B 2>&1
cd /root/pe-fin/mt5 || exit 1
export OPENBLAS_NUM_THREADS=1 WINEPREFIX=/root/.mt5wine WINEARCH=win64 WINEDEBUG=-all DISPLAY=:99
TD="$WINEPREFIX/drive_c/Program Files/MetaTrader 5"
pkill -f mt5_bridge.py; wineserver -k; sleep 3
pgrep -f "Xvfb :99" >/dev/null || (Xvfb :99 -screen 0 1280x1024x24 >/dev/null 2>&1 &); sleep 2
python3 - <<'PY'
import sys,os; sys.path.insert(0,'/root/pe-queue/runner'); import creds; E=creds.all_vars()
ini=f"""[Common]\r\nLogin={E['MT5_LOGIN']}\r\nPassword={E['MT5_PASSWORD']}\r\nServer={E.get('MT5_SERVER','Darwinex-Demo')}\r\nKeepPrivate=1\r\nNewsEnable=0\r\n[Experts]\r\nEnabled=1\r\nAllowLiveTrading=1\r\nAllowDllImport=0\r\n"""
p='/root/pe-fin/mt5/login.ini'; open(p,'w').write(ini); os.chmod(p,0o600); print('startup config written (600)')
PY
# terminal keeper: always start with the login config from now on
cat > run_terminal.sh <<'SH'
#!/bin/bash
export OPENBLAS_NUM_THREADS=1 WINEPREFIX=/root/.mt5wine WINEARCH=win64 WINEDEBUG=-all DISPLAY=:99
pgrep -f "Xvfb :99" >/dev/null || (Xvfb :99 -screen 0 1280x1024x24 >/dev/null 2>&1 &)
sleep 2; pgrep -f terminal64.exe >/dev/null || (wine "$WINEPREFIX/drive_c/Program Files/MetaTrader 5/terminal64.exe" /portable "/config:Z:\\root\\pe-fin\\mt5\\login.ini" >/dev/null 2>&1 &)
SH
chmod +x run_terminal.sh; ./run_terminal.sh
say "538: terminal started with demo login config; waiting for authorisation"
TL(){ f=$(ls -t "$TD"/logs/*.log 2>/dev/null | head -1); [ -n "$f" ] && iconv -f UTF-16LE -t UTF-8 "$f" 2>/dev/null | tr -d '\r'; }
for i in $(seq 1 36); do TL | grep -qiE "authoriz|synchroniz" && break; sleep 10; done
say "terminal log: $(TL | grep -iE 'authoriz|synchroni|connect|login|invalid|fail|update' | tail -6 | cut -c1-160 | tr '\n' '|')"
grep -q "portable=True" mt5_bridge.py || sed -i "s|timeout=120000,login=|timeout=180000,portable=True,login=|" mt5_bridge.py
grep -c "portable=True" mt5_bridge.py | sed 's/^/bridge portable patch: /'
# run_bridge.sh must start the terminal (with config) before the bridge
grep -q run_terminal.sh run_bridge.sh || sed -i 's#^pgrep -f mt5_bridge.py >/dev/null \&\& exit 0#pgrep -f mt5_bridge.py >/dev/null \&\& exit 0\n/root/pe-fin/mt5/run_terminal.sh; sleep 20#' run_bridge.sh
: > bridge.log
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
say "DONE 538"; /root/pe-fin/team/publish.sh >/dev/null 2>&1; echo published
