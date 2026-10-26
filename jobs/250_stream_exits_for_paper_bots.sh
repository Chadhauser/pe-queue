#!/bin/bash
# 250: SUB-SECOND EXITS. The late lay-Over and xG paper bots detected goals and priced their exits from the 1-minute recorder samples.
# They now use the Streaming tape first (stream_ticks: every book change, ~50 ms): goal = Over best back falls 30%+ / draw best back
# rises 25%+ between consecutive sane ticks on that runner; exit price = the first sane tick >= goal + 120 s. Recorder samples remain
# the fallback when the stream has no ticks for that market. Restart both bots + heartbeats.
set -e
cat > /root/pe-xg/stream_helpers.py <<'PYFILE'
SANE_T="back_px IS NOT NULL AND lay_px IS NOT NULL AND lay_px<=back_px*1.2"
def stream_goal_after(cur,market_id,sel_like,direction,ts):
    """first stream tick after ts where the runner's best back moves through the goal threshold; direction 'drop' (<=0.7x) or 'jump' (>=1.25x)"""
    cond="back_px<=pb*0.7" if direction=='drop' else "back_px>=pb*1.25 AND back_px>=pl*1.25"
    cur.execute(f"""WITH d AS (SELECT ts_recv, back_px, lag(back_px) OVER (ORDER BY ts_recv) pb, lag(lay_px) OVER (ORDER BY ts_recv) pl
                               FROM stream_ticks WHERE market_id=%s AND lower(sel) LIKE %s AND {SANE_T} AND ts_recv>%s-interval '10 minutes')
                    SELECT ts_recv FROM d WHERE pb IS NOT NULL AND {cond} AND ts_recv>%s ORDER BY ts_recv LIMIT 1""",(market_id,sel_like,ts,ts))
    r=cur.fetchone(); return r[0] if r else None
def stream_back_at(cur,market_id,sel_like,ts):
    cur.execute(f"SELECT back_px, ts_recv FROM stream_ticks WHERE market_id=%s AND lower(sel) LIKE %s AND {SANE_T} AND ts_recv>=%s ORDER BY ts_recv LIMIT 1",(market_id,sel_like,ts)); return cur.fetchone()
def stream_has(cur,market_id):
    cur.execute("SELECT 1 FROM stream_ticks WHERE market_id=%s LIMIT 1",(market_id,)); return cur.fetchone() is not None
PYFILE
python3 - <<'PY'
# ---- late_over_paper.py
p='/root/pe-xg/late_over_paper.py'; s=open(p).read(); n=0
if 'stream_helpers' not in s:
    s=s.replace("sys.path.insert(0,'/root/pe-bot'); from bot_core import DB","sys.path.insert(0,'/root/pe-bot'); from bot_core import DB\nsys.path.insert(0,'/root/pe-xg'); from stream_helpers import stream_goal_after, stream_back_at, stream_has",1); n+=1
old="""def over_drop_after(mid,ts):
    cur.execute(f\"\"\"WITH d AS"""
new="""def over_drop_after(mid,ts):
    if stream_has(cur,mid):
        g=stream_goal_after(cur,mid,'over%','drop',ts)
        if g is not None: return g
    cur.execute(f\"\"\"WITH d AS"""
assert old in s; s=s.replace(old,new,1); n+=1
old2="""def back_from(mid,ts=None,minute=None):
    if ts is not None: cur.execute("""
new2="""def back_from(mid,ts=None,minute=None):
    if ts is not None and stream_has(cur,mid):
        r=stream_back_at(cur,mid,'over%',ts)
        if r: return r
    if ts is not None: cur.execute("""
assert old2 in s; s=s.replace(old2,new2,1); n+=1
open(p,'w').write(s); print("late_over patches:",n)
# ---- xg_paper.py
p='/root/pe-xg/xg_paper.py'; s=open(p).read(); n=0
if 'stream_helpers' not in s:
    s=s.replace("sys.path.insert(0,'/root/pe-bot'); from bot_core import DB","sys.path.insert(0,'/root/pe-bot'); from bot_core import DB\nsys.path.insert(0,'/root/pe-xg'); from stream_helpers import stream_goal_after, stream_back_at, stream_has",1); n+=1
old="""def draw_jump_after(mid,ts):
    cur.execute(f\"\"\"WITH d AS"""
new="""def draw_jump_after(mid,ts):
    if stream_has(cur,mid):
        g=stream_goal_after(cur,mid,'%draw%','jump',ts)
        if g is not None: return g
    cur.execute(f\"\"\"WITH d AS"""
assert old in s; s=s.replace(old,new,1); n+=1
old2="""def over_drop_after(mid,ts):
    cur.execute(f\"\"\"WITH d AS"""
new2="""def over_drop_after(mid,ts):
    if stream_has(cur,mid):
        g=stream_goal_after(cur,mid,'over%','drop',ts)
        if g is not None: return g
    cur.execute(f\"\"\"WITH d AS"""
assert old2 in s; s=s.replace(old2,new2,1); n+=1
old3="""def back_at(mid,mkt,sel,ts):
    cur.execute("""
new3="""def back_at(mid,mkt,sel,ts):
    if stream_has(cur,mid):
        like='over%' if sel=='OVER' else ('%draw%' if sel=='DRAW' else None)
        if like:
            r=stream_back_at(cur,mid,like,ts)
            if r: return r
    cur.execute("""
assert old3 in s; s=s.replace(old3,new3,1); n+=1
open(p,'w').write(s); print("xg patches:",n)
PY
python3 -m py_compile /root/pe-xg/stream_helpers.py /root/pe-xg/late_over_paper.py /root/pe-xg/xg_paper.py
pkill -f late_over_paper.py || true; pkill -f xg_paper.py || true; sleep 2; /root/pe-xg/keepalive_lo.sh; /root/pe-xg/keepalive.sh; sleep 70
pgrep -af "late_over_paper|xg_paper" | head -2; tail -2 /root/pe-xg/late_over.log; tail -2 /root/pe-xg/xg.log
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
k=psycopg2.connect(DB,sslmode='require').cursor()
k.execute("SELECT * FROM late_over_heartbeat"); print("late-over hb:",k.fetchall()); k.execute("SELECT * FROM xg_heartbeat"); print("xg hb:",k.fetchall())
k.execute("SELECT sport, mkt, count(*), count(DISTINCT market_id) FROM stream_ticks WHERE ts_recv>now()-interval '10 minutes' GROUP BY 1,2"); print("stream last 10 min:",k.fetchall())
PY
