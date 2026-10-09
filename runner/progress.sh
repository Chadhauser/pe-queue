#!/bin/bash
# Runs every 5 min independently of the runner (not under its lock): heartbeat + stream the tail of the running job's log
# into job_results so progress is visible from the database while a long job runs.
python3 /root/pe-queue/runner/report.py heartbeat >/dev/null 2>&1
python3 - <<'PY'
import sys, os, glob, psycopg2
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("SELECT job FROM job_results WHERE status='running'")
for (job,) in cur.fetchall():
    f=f"/root/pe-queue-logs/{job}.log"
    if os.path.exists(f):
        s=open(f,errors='replace').read()[-20000:]
        cur.execute("UPDATE job_results SET log=%s WHERE job=%s AND status='running'",("[PROGRESS, partial]\n"+s,job))
PY
