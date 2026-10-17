#!/bin/bash
# 096: DISK PRESSURE v2 (Sat 17 Oct, Railway "nearly full" again — DB 21.9 GB of 30). Causes, measured: ip_tape writing 4-8M
# rows/day (~1 GB/day) and xx_tape (Matchbook) 4.5M rows/day (~1 GB/day). Fixes, in order:
#  1. retention: ip_tape and xx_tape keep 10 days (reopen scan needs 7; ip_reopen itself is kept forever and is tiny).
#  2. ingest rate: ip_tape thin sample 15s -> 30s and market cap 240 -> 150; xx_tape loop 5s -> 20s.
#  3. VACUUM (not FULL - no lock, no 2x space) so freed pages are reused; growth then stops at today's size.
#  4. report the four legacy Contabo loggers (bf_price_log / tennis / racing / golf, 5.4 GB) - last write time, so we can
#     decide whether they are still needed now the liq and ip recorders cover the same ground.
python3 - <<'PY'
import sys, re, subprocess, psycopg2
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("SET statement_timeout='900s'")
def gb(): cur.execute("SELECT round(pg_database_size(current_database())/1e9,2)"); return cur.fetchone()[0]
print("DB GB before",gb(),flush=True)
for t,col in (('ip_tape','ts'),('xx_tape','ts')):
    cur.execute(f"DELETE FROM {t} WHERE {col} < now()-interval '10 days'"); print(t,"deleted",cur.rowcount,flush=True)
for t in ('ip_tape','xx_tape','liq_sample','liq_goal_depth'):
    cur.execute(f"VACUUM (ANALYZE) {t}"); print("vacuumed",t,flush=True)
print("DB GB after vacuum (pages now reusable; OS size only shrinks on VACUUM FULL)",gb())
for t,c in (('bf_price_log','captured_at'),('bf_tennis_log','captured_at'),('bf_racing_log','captured_at'),('bf_golf_log','captured_at')):
    try: cur.execute(f"SELECT max({c}), count(*) FILTER (WHERE {c}>now()-interval '1 day') FROM {t}"); print("legacy logger",t,"last write",*cur.fetchone())
    except Exception as e: print(t,repr(e)[:80])
PY
# 2. slow the recorders
python3 - <<'PY'
p='/root/pe-ip/ip_recorder.py'; s=open(p).read()
s=s.replace("time.time()-last_write[mid]>=15","time.time()-last_write[mid]>=30").replace("[:240]","[:150]").replace("if len(new)>240:","if len(new)>150:")
open(p,'w').write(s); print("ip_recorder: 30s sampling, 150-market cap")
p='/root/pe-xx/xx_recorder.py'; s=open(p).read()
s=s.replace("\n    time.sleep(5)\n","\n    time.sleep(20)\n"); open(p,'w').write(s); print("xx_recorder: 20s loop")
PY
python3 -m py_compile /root/pe-ip/ip_recorder.py /root/pe-xx/xx_recorder.py || exit 1
pkill -f ip_recorder.py; pkill -f xx_recorder.py; echo "recorders restarted by cron keepalive within 60s"
sleep 75; pgrep -af "ip_recorder|xx_recorder"
echo "legacy logger processes:"; pgrep -af "price_log|tennis_log|racing_log|golf_log|logger" | head
crontab -l | grep -i -E "log|watchdog" | head
