#!/bin/bash
# 285: Peter 29 Oct 05:47: "I am getting a load of notifications on my phone ... can these stop?" — 259 gated send_push.py, but
# something still sends (a sender that imports pywebpush directly, e.g. the goal-signal /positions app or an older bot).
# Stop it at the source: (1) list every file that can send a web push; (2) move the VAPID key file aside so no sender can sign a
# push; (3) back up and empty push_subscriptions. Reversible: restore vapid.env and the backup table.
set -e
echo "== senders"; grep -rl "webpush\|pywebpush\|vapid" /root/pe-* --include=*.py 2>/dev/null | grep -v __pycache__ || true
echo "== crontab lines mentioning push"; crontab -l | grep -i push || true
echo "== processes mentioning push"; pgrep -af "push|positions|goal_signal|signal" | head || true
[ -f /root/pe-push/vapid.env ] && mv /root/pe-push/vapid.env /root/pe-push/vapid.env.OFF && echo "vapid.env moved aside"
touch /root/pe-push/PUSH_OFF
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require'); c.autocommit=True; k=c.cursor()
k.execute("CREATE TABLE IF NOT EXISTS push_subscriptions_backup AS SELECT * FROM push_subscriptions WHERE false")
k.execute("INSERT INTO push_subscriptions_backup SELECT * FROM push_subscriptions"); print("subscriptions backed up:",k.rowcount)
k.execute("DELETE FROM push_subscriptions"); print("subscriptions removed:",k.rowcount)
try:
    k.execute("SELECT ts, sent, left(body,80) FROM push_log ORDER BY ts DESC LIMIT 8"); print("push_log (gated sends):",k.fetchall())
except Exception as e: print("push_log n/a")
PY
echo "pushes are now impossible from this server until vapid.env is restored and subscriptions re-registered"
