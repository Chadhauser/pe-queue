#!/bin/bash
# 197: the liquidity recorder samples each Match Odds market roughly once a minute with occasional 2-3 minute gaps; the LTD bot's
# 90-second lookback could miss a whole trigger window. Lookback widened to 4 minutes (entries are unique per market x trigger, so no
# duplicates). Restart + heartbeat.
sed -i "s/AND ts>now()-interval '90 seconds' ORDER BY market_id, ts DESC/AND ts>now()-interval '4 minutes' ORDER BY market_id, ts DESC/" /root/pe-ltd/ltd_paper.py
grep -c "interval '4 minutes' ORDER BY market_id" /root/pe-ltd/ltd_paper.py
python3 -m py_compile /root/pe-ltd/ltd_paper.py && pkill -f ltd_paper.py; sleep 2; /root/pe-ltd/keepalive.sh; sleep 40; pgrep -af ltd_paper.py | head -1; tail -5 /root/pe-ltd/ltd.log
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require').cursor(); c.execute("SELECT * FROM ltd_heartbeat"); print("heartbeat:",c.fetchall())
c.execute("SELECT event_name, competition, trig, entry_minute, lay_px, lay_sz FROM ltd_inplay_paper ORDER BY entry_ts DESC LIMIT 10"); [print("  ",r) for r in c.fetchall()]
PY
