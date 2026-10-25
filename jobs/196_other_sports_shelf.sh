#!/bin/bash
# 196: report — waits for the Factory v3+v4-gates run (195) and prints the per-sport shelf plus the lay-the-draw paper bot's first trades.
if pgrep -f "python3 factory.py" >/dev/null; then echo "factory still running"; tail -1 /root/pe-factory/factory.log; exit 75; fi
grep -v -E "UserWarning|pd.read_sql" /root/pe-factory/factory.log | sed -n '/v4 GATES/,$p' | tail -80
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require').cursor()
c.execute("SELECT * FROM ltd_heartbeat"); print("LTD bot heartbeat:",c.fetchall())
c.execute("SELECT trig, count(*), count(pnl_per_10), round(coalesce(sum(pnl_per_10),0)::numeric,2) FROM ltd_inplay_paper GROUP BY 1 ORDER BY 1"); print("LTD paper by trigger (n, settled, pnl):",c.fetchall())
c.execute("SELECT event_name, competition, trig, lay_px, exit_reason, pnl_per_10 FROM ltd_inplay_paper ORDER BY entry_ts DESC LIMIT 12"); [print("  ",r) for r in c.fetchall()]
PY
