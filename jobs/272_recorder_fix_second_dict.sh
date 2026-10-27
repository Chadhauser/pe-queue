#!/bin/bash
# 272: LIQUIDITY RECORDER DOWN SINCE 09:31 — my 265 patch updated only the first of two market-type dicts on the catalogue line;
# the fallback dict still lacked DRAW_NO_BET -> KeyError on startup -> crash loop under keepalive. Fix: one shared dict, used in
# both places; restart; prove rows within 2 minutes. (Integrity flagged "liq rows last hour = 0" at 11:30 and 13:30 but pushes
# are off — the morning read must include the integrity table, not just the job list.)
set -e
python3 - <<'PY'
import re
p='/root/pe-liq/liq_recorder.py'; s=open(p).read()
MAP="{'MATCH_ODDS':'MO','CORRECT_SCORE':'CS','OVER_UNDER_25':'OU25','OVER_UNDER_15':'OU15','OVER_UNDER_35':'OU35','BOTH_TEAMS_TO_SCORE':'BTTS','ASIAN_HANDICAP':'AH','DRAW_NO_BET':'DNB','OVER_UNDER_05':'OU05','TEAM_A_1':'TA1','TEAM_B_1':'TB1'}"
n=0
for m in list(re.finditer(r"\{'MATCH_ODDS':'MO','CORRECT_SCORE':'CS'[^}]*\}",s)):
    pass
s2,n=re.subn(r"\{'MATCH_ODDS':'MO','CORRECT_SCORE':'CS'[^}]*\}",MAP,s)
assert n>=2, f"expected 2 dict literals, found {n}"
open(p,'w').write(s2); print("dict literals replaced:",n)
PY
python3 -m py_compile /root/pe-liq/liq_recorder.py
pkill -f liq_recorder.py || true; sleep 2; nohup /root/pe-liq/keepalive.sh >/dev/null 2>&1 &
sleep 120; echo "== process"; pgrep -af liq_recorder.py | head -1 || echo NOT RUNNING; echo "== log"; tail -4 /root/pe-liq/recorder.log
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
k=psycopg2.connect(DB,sslmode='require').cursor()
k.execute("SELECT mkt, count(*), count(DISTINCT market_id) FROM liq_sample WHERE ts>now()-interval '3 minutes' GROUP BY 1 ORDER BY 1"); print("rows last 3 min:",k.fetchall())
k.execute("SELECT sel, back_px, lay_px FROM liq_sample WHERE mkt='DNB' ORDER BY ts DESC LIMIT 3"); print("DNB:",k.fetchall())
k.execute("SELECT * FROM liq_heartbeat"); print("liq hb:",k.fetchall())
PY
