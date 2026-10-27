#!/bin/bash
# 271: the liquidity recorder wrote NOTHING after 265's restart (last row 09:31:15). Show the log, then trim the market list back
# to the proven set + DRAW_NO_BET, restart, and prove rows flow. Watchdog would restart it, but a restart does not fix a bad list.
set -e
echo "== recorder log tail"; tail -25 /root/pe-liq/recorder.log || true
echo "== process"; pgrep -af liq_recorder.py || echo "not running"
python3 - <<'PY'
p='/root/pe-liq/liq_recorder.py'; s=open(p).read(); o=s
s=s.replace("'ASIAN_HANDICAP','DRAW_NO_BET','OVER_UNDER_05','TEAM_A_1','TEAM_B_1'):","'ASIAN_HANDICAP','DRAW_NO_BET'):",1)
print("list trimmed" if s!=o else "list unchanged"); open(p,'w').write(s)
print([l.strip()[:170] for l in s.splitlines() if 'for mt in' in l])
PY
python3 -m py_compile /root/pe-liq/liq_recorder.py; pkill -f liq_recorder.py || true; sleep 2; nohup /root/pe-liq/keepalive.sh >/dev/null 2>&1 &
sleep 150; echo "== log after restart"; tail -8 /root/pe-liq/recorder.log
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
k=psycopg2.connect(DB,sslmode='require').cursor()
k.execute("SELECT mkt, count(*) FROM liq_sample WHERE ts>now()-interval '3 minutes' GROUP BY 1 ORDER BY 1"); print("rows last 3 min:",k.fetchall())
k.execute("SELECT sel, back_px, lay_px FROM liq_sample WHERE mkt='DNB' ORDER BY ts DESC LIMIT 4"); print("DNB:",k.fetchall())
PY
