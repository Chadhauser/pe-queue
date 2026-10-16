#!/bin/bash
# 090: inspect the web-push sender so the M1 alerts (weekend card trades) can be delivered to Peter's phone the same way the goal signal is.
echo "== /root/pe-push =="; ls -la /root/pe-push; echo "== crontab push lines =="; crontab -l | grep -i push
echo "== send_push.py =="; cat /root/pe-push/send_push.py
echo "== pg_bot goal detection (grep) =="; grep -n "goal\|reopen\|SUSPENDED" /root/pe-pg/pg_bot.py | head -40
echo "== liq_goal_depth columns =="; python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require').cursor()
for t in ('liq_goal_depth','push_subscriptions','push_subs','bot_orders'):
    c.execute("SELECT string_agg(column_name,',') FROM information_schema.columns WHERE table_name=%s",(t,)); print(t,c.fetchone()[0])
c.execute("SELECT table_name FROM information_schema.tables WHERE table_name ILIKE '%push%' OR table_name ILIKE '%subscri%'"); print("push tables",c.fetchall())
PY
