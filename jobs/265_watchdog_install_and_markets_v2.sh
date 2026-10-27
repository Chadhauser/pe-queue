#!/bin/bash
# 265: 254 died on an 'ls' of a path that doesn't exist (racing MM keepalive lives at /root/pe-race/keepalive_mm_stream.sh), so the
# WATCHDOG was never installed. Install it now (correct paths), run it once. Also: NEXT_GOAL is not an in-play market type on
# Betfair (254's census) — replace it with three that are: DRAW_NO_BET (DNB), OVER_UNDER_05 (OU05), TEAM_A_1/TEAM_B_1 (TA1/TB1,
# team to score). Raw selection names for every market outside MO/OU25/CS.
set -e
echo "== watchdog"
python3 - <<'PY'
p='/root/pe-push/watchdog.py'
import os
if not os.path.exists(p): raise SystemExit("watchdog.py missing — 254 wrote it before failing? no: write again")
s=open(p).read(); s=s.replace("'/root/pe-racing/keepalive_stream.sh'","'/root/pe-race/keepalive_mm_stream.sh'"); open(p,'w').write(s); print("paths fixed")
PY
python3 -m py_compile /root/pe-push/watchdog.py
( crontab -l 2>/dev/null | grep -v "pe-push/watchdog.py" ; echo "*/5 * * * * python3 /root/pe-push/watchdog.py >> /root/pe-push/watchdog.log 2>&1" ) | crontab -
python3 /root/pe-push/watchdog.py; echo "watchdog installed + first run"
echo "== recorder markets v2"
python3 - <<'PY'
import re
p='/root/pe-liq/liq_recorder.py'; s=open(p).read(); o=s
s=s.replace("'ASIAN_HANDICAP','NEXT_GOAL'):","'ASIAN_HANDICAP','DRAW_NO_BET','OVER_UNDER_05','TEAM_A_1','TEAM_B_1'):",1)
s=s.replace("'ASIAN_HANDICAP':'AH','NEXT_GOAL':'NG'}","'ASIAN_HANDICAP':'AH','DRAW_NO_BET':'DNB','OVER_UNDER_05':'OU05','TEAM_A_1':'TA1','TEAM_B_1':'TB1'}",1)
s=s.replace("    if meta['mkt'] in ('AH','NG'): return low.upper()[:40]","    if meta['mkt'] not in ('MO','OU25','CS'): return low.upper()[:40]",1)
assert s!=o and "'DNB'" in s and "not in ('MO','OU25','CS')" in s, "anchors missing"
open(p,'w').write(s); print("markets:",[l.strip()[:160] for l in s.splitlines() if 'for mt in' in l])
PY
python3 -m py_compile /root/pe-liq/liq_recorder.py; pkill -f liq_recorder.py || true; sleep 2; nohup /root/pe-liq/keepalive.sh >/dev/null 2>&1 &
sleep 150
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
k=psycopg2.connect(DB,sslmode='require').cursor()
k.execute("SELECT mkt, count(*), count(DISTINCT market_id) FROM liq_sample WHERE ts>now()-interval '3 minutes' GROUP BY 1 ORDER BY 1"); print("rows last 3 min by market:",k.fetchall())
k.execute("SELECT mkt, sel, back_px, lay_px FROM liq_sample WHERE mkt IN ('DNB','OU05','TA1','TB1','AH') AND ts>now()-interval '3 minutes' ORDER BY ts DESC LIMIT 8"); [print("  ",r) for r in k.fetchall()]
k.execute("SELECT * FROM liq_heartbeat"); print("liq hb:",k.fetchall())
k.execute("SELECT * FROM watchdog_log ORDER BY ts DESC LIMIT 5"); print("watchdog log:",k.fetchall())
PY
crontab -l | grep -c . | sed 's/^/cron lines: /'
