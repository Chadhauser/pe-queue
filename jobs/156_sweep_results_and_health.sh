#!/bin/bash
# 156: report job — waits for the v4 sport sweep to finish (exit 75 = check again next cycle), then prints its results and the
# health of the two bots touched today (racing recorder after the 147 regression; stats recorder after the 155 pacing change).
echo "== health"; date -u
pgrep -af "race_swing.py|race_mm.py|stats_recorder.py|liq_recorder.py|ip_recorder.py|clv_bot.py|dog_paper.py|fav_paper.py|m1_alert.py" | awk '{print $3}' | sort | uniq -c
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require').cursor()
c.execute("SELECT last_seen, round(extract(epoch from now()-last_seen)) age_s, live_markets FROM racing_heartbeat"); print("racing heartbeat:",c.fetchall())
c.execute("SELECT count(*), max(ts) FROM racing_tape WHERE ts>now()-interval '30 minutes'"); print("racing tape last 30 min:",c.fetchone())
c.execute("SELECT count(*) FROM racing_mm_paper WHERE quoted_ts>now()-interval '2 hours'"); print("mm quotes last 2h:",c.fetchone()[0])
c.execute("SELECT * FROM stats_heartbeat"); print("stats heartbeat (live, matched, remaining):",c.fetchall())
c.execute("SELECT count(*), count(DISTINCT sofa_id), count(*) FILTER (WHERE market_id IS NOT NULL) FROM ip_stats WHERE ts>now()-interval '2 hours'"); print("ip_stats last 2h rows/games/matched:",c.fetchone())
PY
tail -3 /root/pe-race/race.log
echo "== sport sweep"
if pgrep -f sport_sweep.py >/dev/null; then echo "still running:"; tail -2 /root/pe-factory/v4/sport_sweep.log; exit 75; fi
grep -v -E "UserWarning|pd.read_sql| processed" /root/pe-factory/v4/sport_sweep.log | tail -120
