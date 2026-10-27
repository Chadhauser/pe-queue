#!/bin/bash
# 259: Peter 27 Oct: "stop all the notifications to the app". Every push (digest, integrity, watchdog, bot alerts) goes through
# /root/pe-push/send_push.py. It becomes a gate: with /root/pe-push/PUSH_OFF present it logs the message to push_log and sends
# nothing. Everything still runs and still writes to the DB. Remove the file to turn pushes back on.
set -e
cd /root/pe-push
[ -f send_push_real.py ] || cp send_push.py send_push_real.py
cat > send_push.py <<'PYFILE'
import sys, os, subprocess, datetime
MSG=" ".join(sys.argv[1:])
if os.path.exists('/root/pe-push/PUSH_OFF'):
    try:
        import psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
        c=psycopg2.connect(DB,sslmode='require'); c.autocommit=True; k=c.cursor()
        k.execute("CREATE TABLE IF NOT EXISTS push_log (ts TIMESTAMPTZ DEFAULT now(), sent BOOLEAN, body TEXT)"); k.execute("INSERT INTO push_log(sent,body) VALUES (false,%s)",(MSG[:2000],))
    except Exception as e: print("push_log failed",e)
    print("push suppressed (PUSH_OFF)"); sys.exit(0)
sys.exit(subprocess.call([sys.executable,'/root/pe-push/send_push_real.py']+sys.argv[1:]))
PYFILE
touch /root/pe-push/PUSH_OFF
python3 -m py_compile send_push.py && python3 send_push.py "test — should be suppressed" && echo "pushes OFF; messages logged to push_log"
