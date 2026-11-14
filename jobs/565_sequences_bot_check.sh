#!/bin/bash
# 565 (Sat 14 Nov 2026, 06:50). Two things the rescue reading showed this morning:
#  1. The goal monitor is running but an insert fails "Key (id)=(2253968) already exists": the tables restored from dumps on 13 Nov came
#     back with their id sequences behind the data. Reset every serial sequence in the restored tables to max(id). Then restart the monitor.
#  2. The bot's log ends in "psycopg2.InterfaceError: cursor already closed" and no paper order has been written since 12 Nov 23:58.
#     Print the last 60 log lines and the heartbeat, restart it cleanly, and check it is placing again (or print why not).
set -o pipefail
echo "== 1. sequences =="
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
con=psycopg2.connect(creds.pg_local(),sslmode='disable'); con.autocommit=True; c=con.cursor()
for t in ('goal_alerts','goal_live_predictions','goal_timeline','m1_alerts','af_fixtures','af_events','real_trades','goal_alerts_real'):
    try:
        c.execute("select pg_get_serial_sequence(%s,'id')",(t,)); s=c.fetchone()[0]
        if not s: print(t,"no id sequence"); continue
        c.execute(f"select coalesce(max(id),0) from {t}"); mx=c.fetchone()[0]
        c.execute("select last_value from "+s); lv=c.fetchone()[0]
        c.execute("select setval(%s, %s)",(s,max(mx,1))); print(f"{t}: max id {mx}, sequence was {lv}, now {max(mx,1)}")
    except Exception as e: print(t,"ERR",str(e)[:100])
PY
pkill -f "brain/monitor_ht.py"; sleep 25; pgrep -fa "brain/monitor_ht.py" | cut -c1-80; tail -3 /root/pe-brain/monitor_ht.log | cut -c1-200
echo "== 2. bot =="
L=/root/pe-sports/bookie/bookie_v2.log; echo "log lines: $(wc -l < $L)"; grep -n "Traceback\|Error" $L | tail -5 | cut -c1-160; echo "--- last 40 lines"; tail -40 $L | cut -c1-220
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
c=psycopg2.connect(creds.pg_local(),sslmode='disable').cursor()
for name,sql in [("bookie heartbeat","select * from bookie_heartbeat"),("paper orders by day (7d)","select date(ts) d, count(*) from bookie_paper where version='v2' and ts>now()-interval '7 days' group by 1 order by 1"),("passed cells","select sport, count(*) from fair_price_passed group by 1")]:
    try: c.execute(sql); print(name, c.fetchall())
    except Exception as e: c.connection.rollback(); print(name,"ERR",str(e)[:120])
PY
pkill -f "python3 bookie_v2.py"; sleep 45; pgrep -fa "bookie_v2.py" | cut -c1-80; echo "--- after restart"; tail -8 /root/pe-sports/bookie/bookie_v2.log | cut -c1-220
echo "565 done"
