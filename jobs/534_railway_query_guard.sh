#!/bin/bash
# 534 (Sun 8 Nov 2026, 14:30). Railway is the bottleneck between us and money: 24 active queries at 14:15 UTC, the oldest 917 s, a liq_sample
# read 464 s. Long reads from test jobs starve the recorders, the bookie legs (40 s reads) and the board. Guard: every minute, terminate
# any Railway query that has run more than 240 s unless it belongs to a recorder/writer (INSERT/UPDATE/COPY) — tests read in blocks or
# wait; the live tape and the bot come first. Logs every kill to data/railway_guard.log with the query head. Reads stay allowed up to 4 min.
set -o pipefail
mkdir -p /root/pe-guard && cat > /root/pe-guard/railway_guard.py <<'PY'
import sys, datetime, psycopg2
sys.path.insert(0,'/root/pe-queue/runner'); import creds
LIMIT_S=240
con=psycopg2.connect(creds.pg_railway(),sslmode='require',connect_timeout=15); con.autocommit=True; c=con.cursor(); c.execute("SET statement_timeout='20s'")
c.execute("""SELECT pid, now()-query_start AS age, application_name, left(regexp_replace(query,'\\s+',' ','g'),140)
             FROM pg_stat_activity WHERE state='active' AND pid<>pg_backend_pid() AND backend_type='client backend'
               AND now()-query_start > interval '%s seconds'
               AND query !~* '^\\s*(insert|update|copy|delete|create|alter|vacuum|analyze)'
               AND query !~* 'pg_stat_activity|pg_terminate_backend'""" % LIMIT_S)
rows=c.fetchall(); killed=0
with open('/root/pe-guard/railway_guard.log','a') as f:
    for pid,age,app,q in rows:
        c.execute("SELECT pg_terminate_backend(%s)",(pid,)); killed+=int(bool(c.fetchone()[0]))
        f.write(f"{datetime.datetime.utcnow():%Y-%m-%d %H:%M:%S} killed pid {pid} age {age} app {app!r}: {q}\n")
c.execute("SELECT count(*) FROM pg_stat_activity WHERE state='active' AND backend_type='client backend'"); n=c.fetchone()[0]
print(f"active {n} | over {LIMIT_S}s read queries killed {killed}")
PY
python3 -m py_compile /root/pe-guard/railway_guard.py && echo "guard compiles"
echo "-- first pass now --"; timeout 60 python3 /root/pe-guard/railway_guard.py; tail -5 /root/pe-guard/railway_guard.log 2>/dev/null
( crontab -l 2>/dev/null | grep -v 'pe-guard/railway_guard.py'; echo "* * * * * timeout 50 /usr/bin/python3 /root/pe-guard/railway_guard.py >> /root/pe-guard/railway_guard.cron.log 2>&1" ) | crontab -
crontab -l | grep -c railway_guard && echo "guard cron installed (every minute)"
echo "534 done"
