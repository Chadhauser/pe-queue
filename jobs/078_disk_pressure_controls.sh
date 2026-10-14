#!/bin/bash
# 078: DISK PRESSURE (Railway Postgres 80%, DB 13 GB). Immediate, reversible controls:
#  1. ip recorder: thin sampling ALWAYS (1 row per runner per 15s; every suspension/reopen still captured) — cuts ~5x.
#  2. bf_hist_other loader paused (066). 067 BSP files are small (47 MB) and continue.
#  3. Report the size of candidate tables to prune (derived/heartbeat/snapshots) — nothing deleted without Peter.
#  4. Kill any stuck loader process left from 066.
pkill -f "load_basic_history|basic_history_all" 2>/dev/null
python3 - <<'PY'
p='/root/pe-ip/ip_recorder.py'; s=open(p).read()
s=s.replace("thin=len(ids)>60; rows=[]","thin=True; rows=[]   # disk pressure 14 Oct: always thin-sample ip_tape (reopens still full)")
open(p,'w').write(s)
PY
python3 -m py_compile /root/pe-ip/ip_recorder.py && pkill -f ip_recorder.py && echo "ip recorder restarted thin (keepalive)"
python3 - <<'PY'
import sys, psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor()
cur.execute("SELECT pg_size_pretty(pg_database_size(current_database()))"); print("DB size",cur.fetchone()[0])
for t,why in (('tape_snap','old snapshot table'),('tape_ha_snap','old snapshot table'),('brain_heartbeat','heartbeat history - keep last 7 days'),('bf_hist_state','derived from bf_hist_price - rebuildable'),('ch_accounts','Companies House data - not trading'),('runners','?'),('ip_tape','raw in-play tape - keep 14 days then aggregate'),('bf_price_log','own football tape since Aug - keep'),('goal_timeline','engine timeline - keep')):
    try:
        cur.execute(f"SELECT pg_size_pretty(pg_total_relation_size('{t}'))"); print(f"{t:18s} {cur.fetchone()[0]:>8s}  {why}")
    except Exception as e: con.rollback(); print(t,"n/a")
cur.execute("SELECT min(ts)::date, max(ts)::date, count(*) FROM ip_tape"); print("ip_tape span",cur.fetchone())
PY
