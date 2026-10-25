#!/bin/bash
# 219: widen the late lay-Over paper bot to the cells the true-goal engine rates highest: 70'-85' and lay price 2.2-12 (the 5+ band at
# 75'-85' is +£2-7/£10, t 4-6, n 535-611; the previous 1.6-5.0 cap excluded it). ESPN score + price-consistency guards unchanged.
# The 5+ band has no live-ladder replay yet, so its paper rows are evaluated separately (band column).
set -e
python3 - <<'PY'
p='/root/pe-xg/late_over_paper.py'; s=open(p).read(); n=0
a="AND minute BETWEEN 70 AND 77 AND {SANE} AND lay_px BETWEEN 1.6 AND 5.0 AND coalesce(lay_sz,0)>=10"
b="AND minute BETWEEN 70 AND 85 AND {SANE} AND lay_px BETWEEN 2.2 AND 12 AND coalesce(lay_sz,0)>=10"
assert a in s; s=s.replace(a,b,1); n+=1
open(p,'w').write(s); print("patches:",n)
PY
python3 -m py_compile /root/pe-xg/late_over_paper.py
pkill -f late_over_paper.py || true; sleep 2; /root/pe-xg/keepalive_lo.sh; sleep 40; pgrep -af late_over_paper.py | head -1
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
k=psycopg2.connect(DB,sslmode='require').cursor()
k.execute("SELECT * FROM late_over_heartbeat"); print(k.fetchall())
k.execute("SELECT event_name, minute, lay_px, goals, goal_src, exit_reason, pnl_per_10 FROM late_over_paper ORDER BY entry_ts DESC LIMIT 10"); [print("  ",r) for r in k.fetchall()]
PY
