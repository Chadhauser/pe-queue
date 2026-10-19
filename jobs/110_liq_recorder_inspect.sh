#!/bin/bash
# 110: DEFECTS FOUND 19 Oct 05:50 in the football ladder recorder: (a) Everton v Chelsea, Brentford v Liverpool, Betis v Barcelona
# (Sun 18 Oct) have NO rows at all; (b) 25% of goal reopens carry minute 96+ (Leeds v Man Utd both goals = 99) so M1/PG skip them.
# Print the recorder's market selection, minute calculation and heartbeat so the fix is exact, not guessed.
echo "== recorder source: catalogue filter / caps / minute =="; grep -n "listMarketCatalogue\|maxResults\|inPlayOnly\|marketTypeCodes\|competition\|minute\|\[:[0-9]*\]\|len(ids)\|len(new)\|total_matched\|MAX\|cap" /root/pe-liq/liq_recorder.py | head -60
echo "== heartbeat table =="; python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require').cursor()
c.execute("SELECT string_agg(column_name,',') FROM information_schema.columns WHERE table_name='liq_heartbeat'"); print(c.fetchone())
c.execute("SELECT * FROM liq_heartbeat ORDER BY 1 DESC LIMIT 3"); print(c.fetchall())
c.execute("SELECT count(DISTINCT market_id) FROM liq_sample WHERE ts BETWEEN '2026-10-18 15:30' AND '2026-10-18 17:30'"); print("distinct MO/OU markets sampled Sun 15:30-17:30 UTC:",c.fetchone())
c.execute("SELECT DISTINCT left(event_name,28) FROM liq_sample WHERE ts BETWEEN '2026-10-18 16:00' AND '2026-10-18 16:10' AND mkt='MO' ORDER BY 1"); print("MO events sampled Sun 16:00-16:10 UTC:",[r[0] for r in c.fetchall()])
c.execute("SELECT event_name, minute, goal_ts AT TIME ZONE 'Europe/London', ts AT TIME ZONE 'Europe/London' FROM liq_goal_depth WHERE event_name='Leeds v Man Utd' AND offset_s=0 ORDER BY ts LIMIT 4"); print("Leeds rows:",c.fetchall())
PY
echo "== recorder log tail =="; tail -15 /root/pe-liq/recorder.log
