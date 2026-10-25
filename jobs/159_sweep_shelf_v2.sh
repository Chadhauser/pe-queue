#!/bin/bash
# 159: report — waits for the corrected sport sweep (158), prints the shelf, then re-runs goal_capture with its matching fix.
if pgrep -f sport_sweep.py >/dev/null; then echo "sweep still running:"; tail -1 /root/pe-factory/v4/sport_sweep.log; exit 75; fi
echo "== health"; date -u
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require').cursor()
c.execute("SELECT last_seen, round(extract(epoch from now()-last_seen)) age_s, live_markets FROM racing_heartbeat"); print("racing heartbeat:",c.fetchall())
c.execute("SELECT count(*), max(ts) FROM racing_tape WHERE ts>now()-interval '30 minutes'"); print("racing tape last 30 min:",c.fetchone())
c.execute("SELECT exit_reason, count(*), round(sum(pnl_per_10)::numeric,2) FROM racing_mm_paper WHERE quoted_ts>now()-interval '6 hours' GROUP BY 1"); print("mm rounds last 6h:",c.fetchall())
c.execute("SELECT * FROM stats_heartbeat"); print("stats heartbeat:",c.fetchall())
c.execute("SELECT count(*), count(DISTINCT sofa_id), count(*) FILTER (WHERE market_id IS NOT NULL) FROM ip_stats WHERE ts>now()-interval '3 hours'"); print("ip_stats last 3h rows/games/matched:",c.fetchone())
PY
echo "== sport sweep v2 (look-ahead fixed)"
grep -v -E "UserWarning|pd.read_sql| processed" /root/pe-factory/v4/sport_sweep.log | tail -130
echo "== goal_capture (exit after the next goal)"
cd /root/pe-factory && timeout 1500 python3 goal_capture.py 2>&1 | grep -v -E "UserWarning|pd.read_sql| processed" | sed -n '/ALL goals/,/FIRST goal/p;/scorer > 2.5/,/goal before/p'
