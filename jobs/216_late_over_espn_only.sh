#!/bin/bash
# 216: the late lay-Over bot's first three entries show the draw-jump goal count under-counting (Over 2.5 at 1.69 at 70' cannot be a
# 0-0; it is a 2-goal game). Entries now require the ESPN score (goal_src='espn'); the jump count is kept only as a cross-check and a
# price-consistency guard is added (0 goals -> Over lay >= 4.0 at 70'+, 1 goal -> >= 2.2). The three jump-based rows stay, tagged.
set -e
python3 - <<'PY'
p='/root/pe-xg/late_over_paper.py'; s=open(p).read()
old="            if g is None or g>1: continue\n"
new="""            if g is None or g>1 or src!='espn': continue                       # 216: ESPN score only
            if (g==0 and float(lp)<4.0) or (g==1 and float(lp)<2.2): continue   # 216: price must agree with the score
"""
assert old in s; s=s.replace(old,new,1); open(p,'w').write(s); print("patched")
PY
python3 -m py_compile /root/pe-xg/late_over_paper.py
pkill -f late_over_paper.py || true; sleep 2; /root/pe-xg/keepalive_lo.sh; sleep 45; pgrep -af late_over_paper.py | head -1
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require'); c.autocommit=True; k=c.cursor()
k.execute("UPDATE late_over_paper SET goal_src='jumps-v1 (state unverified)' WHERE goal_src='jumps'"); print("tagged:",k.rowcount)
k.execute("SELECT * FROM late_over_heartbeat"); print(k.fetchall())
PY
