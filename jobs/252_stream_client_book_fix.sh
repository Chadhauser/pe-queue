#!/bin/bash
# 252: STREAM BOOK FIX. The stream client subscribes with EX_BEST_OFFERS_DISP, and that field arrives as 'bdatb'/'bdatl' (display
# ladders), not 'batb'/'batl'. The delta code only read batb/batl, so every stream row since 25 Oct has NULL back/lay (LTP only,
# ~100 s between rows) — the sub-second exits (250) and the stream market maker (225) have been running blind and falling back to
# the 1-minute recorder. Fix: read both key pairs. Restart, then prove rows now carry a book and tick cadence is sub-second.
set -e
python3 - <<'PY'
p='/root/pe-stream/stream_client.py'; s=open(p).read(); o=s
s=s.replace("for lvl,px,sz in rc.get('batb',[]):","for lvl,px,sz in rc.get('batb',[])+rc.get('bdatb',[]):",1)
s=s.replace("for lvl,px,sz in rc.get('batl',[]):","for lvl,px,sz in rc.get('batl',[])+rc.get('bdatl',[]):",1)
assert s!=o and "bdatb" in s and "bdatl" in s, "patch anchors not found"
open(p,'w').write(s); print("stream client patched: bdatb/bdatl accepted")
PY
python3 -m py_compile /root/pe-stream/stream_client.py
pkill -f stream_client.py || true; sleep 2; nohup /root/pe-stream/keepalive.sh >/dev/null 2>&1 &
sleep 120; pgrep -af stream_client.py | head -1; tail -3 /root/pe-stream/stream.log
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
k=psycopg2.connect(DB,sslmode='require').cursor()
k.execute("""SELECT sport, mkt, count(*) n, sum(CASE WHEN back_px IS NOT NULL THEN 1 ELSE 0 END) with_back, round(avg(latency_ms)) lat
             FROM stream_ticks WHERE ts_recv>now()-interval '2 minutes' GROUP BY 1,2"""); print("last 2 min:",k.fetchall())
k.execute("""WITH d AS (SELECT market_id, ts_recv-lag(ts_recv) OVER (PARTITION BY market_id,sel_id ORDER BY ts_recv) g FROM stream_ticks WHERE ts_recv>now()-interval '2 minutes')
             SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(epoch FROM g)) med_gap_s FROM d WHERE g IS NOT NULL"""); print("median gap between ticks (s):",k.fetchone())
k.execute("SELECT sport, mkt, sel, back_px, back_sz, lay_px, lay_sz, ltp FROM stream_ticks WHERE back_px IS NOT NULL ORDER BY ts_recv DESC LIMIT 5"); [print("  ",r) for r in k.fetchall()]
PY
