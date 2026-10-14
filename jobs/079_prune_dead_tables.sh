#!/bin/bash
# 079: Peter approved 14 Oct 15:47 UK: drop tape_snap, tape_ha_snap (old snapshot tables), bf_hist_state (derived, rebuildable from
# bf_hist_price), trim brain_heartbeat to 7 days. Then VACUUM so the space is actually returned. Sizes printed before/after.
python3 - <<'PY'
import sys, psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
def size(): cur.execute("SELECT pg_size_pretty(pg_database_size(current_database()))"); return cur.fetchone()[0]
print("before",size())
for t in ('tape_snap','tape_ha_snap','bf_hist_state'):
    try: cur.execute(f"SELECT pg_size_pretty(pg_total_relation_size('{t}'))"); s=cur.fetchone()[0]; cur.execute(f"DROP TABLE IF EXISTS {t}"); print("dropped",t,s)
    except Exception as e: print("skip",t,repr(e)[:80])
try:
    cur.execute("SELECT column_name FROM information_schema.columns WHERE table_name='brain_heartbeat' AND data_type LIKE 'timestamp%' LIMIT 1"); c=cur.fetchone()
    if c:
        cur.execute(f"DELETE FROM brain_heartbeat WHERE {c[0]} < now() - interval '7 days'"); print("brain_heartbeat rows deleted",cur.rowcount); cur.execute("VACUUM FULL brain_heartbeat")
except Exception as e: print("brain_heartbeat",repr(e)[:80])
print("after",size())
PY
