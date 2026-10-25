#!/bin/bash
# 226: API-Football plan upgraded by Peter (16:04). Restart the xG recorder so the 15-minute quota back-off clears now, poll each matched
# fixture every 120 s instead of 180 s (budget is now 75k/day; matched-only + 18'+ + <=2 goals targeting stays), and verify within
# two minutes that xG rows are flowing and the heartbeat shows the new remaining count.
set -e
python3 - <<'PY'
p='/root/pe-stats/stats_recorder.py'; s=open(p).read()
a="if fid in last_poll and time.time()-last_poll[fid]<180: continue"
if a in s: s=s.replace(a,"if fid in last_poll and time.time()-last_poll[fid]<120: continue",1); print("gap 120 s")
open(p,'w').write(s)
PY
python3 -m py_compile /root/pe-stats/stats_recorder.py
pkill -f stats_recorder.py || true; sleep 2; /root/pe-stats/keepalive.sh; sleep 110; pgrep -af stats_recorder.py | head -1; tail -4 /root/pe-stats/stats.log
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require').cursor()
c.execute("SELECT * FROM stats_heartbeat"); print("api-football heartbeat (live, matched, remaining):",c.fetchall())
c.execute("SELECT count(*), count(DISTINCT sofa_id), max(ts) FROM ip_stats WHERE ts>now()-interval '5 minutes' AND h_xg IS NOT NULL"); print("xG rows last 5 min (rows, fixtures, latest):",c.fetchone())
c.execute("SELECT event_name, minute, hs, \"as\", h_xg, a_xg, h_sot, a_sot FROM ip_stats WHERE ts>now()-interval '5 minutes' AND h_xg IS NOT NULL ORDER BY ts DESC LIMIT 6"); [print("  ",r) for r in c.fetchall()]
c.execute("SELECT * FROM xg_heartbeat"); print("xg paper bot (candidates, with_xg, open):",c.fetchall())
PY
