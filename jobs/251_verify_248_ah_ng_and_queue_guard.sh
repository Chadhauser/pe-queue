#!/bin/bash
# 251: after 248 (which held the queue by running the recorder keepalive in the foreground — fixed in runner.sh with a 3 h timeout):
# make sure the liquidity recorder is up ONCE with the AH/NG code, then show AH/NG rows and heartbeat. Daemons only ever via nohup &.
set -e
grep -c "ASIAN_HANDICAP" /root/pe-liq/liq_recorder.py | sed 's/^/AH refs in recorder: /'
n=$(pgrep -fc "python3 liq_recorder.py" || true); echo "recorder processes: $n"
if [ "$n" = "0" ]; then nohup /root/pe-liq/keepalive.sh >/dev/null 2>&1 & sleep 5; echo "recorder started"; fi
if [ "$n" -gt 1 ]; then pkill -f "python3 liq_recorder.py" || true; sleep 3; nohup /root/pe-liq/keepalive.sh >/dev/null 2>&1 & sleep 5; echo "duplicates cleared, restarted once"; fi
pgrep -af "liq_recorder.py" | head -3
sleep 90
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
k=psycopg2.connect(DB,sslmode='require').cursor()
k.execute("SELECT mkt, count(*), count(DISTINCT market_id) FROM liq_sample WHERE ts>now()-interval '5 minutes' GROUP BY mkt ORDER BY 1"); print("rows last 5 min by market:",k.fetchall())
k.execute("SELECT mkt, count(*) FROM liq_sample WHERE mkt IN ('AH','NG') AND ts>now()-interval '3 hours' GROUP BY 1"); print("AH/NG rows last 3 h:",k.fetchall())
k.execute("SELECT event_name, mkt, sel, back_px, lay_px, ts FROM liq_sample WHERE mkt IN ('AH','NG') ORDER BY ts DESC LIMIT 6"); [print("  ",r) for r in k.fetchall()]
for t in ('liq_heartbeat','recorder_heartbeat'):
    try: k.execute(f"SELECT * FROM {t} ORDER BY 1 DESC LIMIT 1"); print(t,k.fetchone())
    except Exception as e: k.connection.rollback(); print(t,"n/a")
PY
