#!/bin/bash
# 343: RESTART STALE DAEMONS. The Postgres restart at 19:30 UTC on 3 Nov (memory cap) killed long-lived connections; the
# pre-off scalper's keepalive died with it (heartbeat stale 700+ min). Restart it the way 328 did, make the keepalive
# survive reboots via cron, and report which other heartbeats are stale and which script owns each (no restarts beyond
# the scalper here: the owners of 'racing', 'fin', 'logger', 'late_over' are reported first).
set -o pipefail
echo "== scalper"; pgrep -af "preoff_scalp" | sed 's/postgres[^ ]*/<dsn>/g' || echo "not running"
pkill -f keepalive_preoff_scalp.sh 2>/dev/null; pkill -f preoff_scalp_paper.py 2>/dev/null; sleep 2
nohup /root/pe-race/keepalive_preoff_scalp.sh >/dev/null 2>&1 &
sleep 20; pgrep -af "preoff_scalp" | sed 's/postgres[^ ]*/<dsn>/g'
# watchdog: if the heartbeat is older than 10 min (hung on a dead socket, as on 3 Nov), kill and relaunch
cat > /root/pe-race/watchdog_preoff_scalp.sh <<'SH'
#!/bin/bash
age=$(python3 - <<'PY'
import sys,psycopg2
try:
    sys.path.insert(0,'/root/pe-queue/runner'); import creds
    c=psycopg2.connect(creds.pg_railway(), sslmode='require', connect_timeout=15).cursor(); c.execute("SET statement_timeout='30s'")
    c.execute("select extract(epoch from now()-max(last_seen))/60 from preoff_scalp_heartbeat"); print(int(c.fetchone()[0] or 9999))
except Exception: print(-1)
PY
)
if [ "$age" -gt 10 ] || ! pgrep -f keepalive_preoff_scalp.sh >/dev/null; then
  pkill -f keepalive_preoff_scalp.sh; pkill -f preoff_scalp_paper.py; sleep 2
  nohup /root/pe-race/keepalive_preoff_scalp.sh >/dev/null 2>&1 &
  echo "$(date -u +%FT%TZ) restarted (heartbeat age $age min)" >> /root/pe-race/watchdog.log
fi
SH
chmod +x /root/pe-race/watchdog_preoff_scalp.sh
( crontab -l 2>/dev/null | grep -v -E "keepalive_preoff_scalp|watchdog_preoff_scalp"; echo "@reboot nohup /root/pe-race/keepalive_preoff_scalp.sh >/dev/null 2>&1 &"; echo "*/5 * * * * /root/pe-race/watchdog_preoff_scalp.sh" ) | crontab -
crontab -l | grep preoff
tail -5 /root/pe-race/preoff_scalp.log 2>/dev/null | sed 's/postgres[^ ]*/<dsn>/g'
echo "== heartbeats (name, age min)"
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
con=psycopg2.connect(creds.pg_railway(), sslmode='require', connect_timeout=20); cur=con.cursor(); cur.execute("SET statement_timeout='120s'")
cur.execute("select table_name from information_schema.tables where table_name like '%heartbeat%' order by 1")
for (t,) in cur.fetchall():
    try:
        cur.execute(f"select column_name from information_schema.columns where table_name=%s and data_type like 'timestamp%%'",(t,)); cols=[c[0] for c in cur.fetchall()]
        if not cols: print(t,"no ts col"); continue
        cur.execute(f"select round(extract(epoch from now()-max({cols[0]}))/60) from {t}"); print(f"{t:32s} {cur.fetchone()[0]} min")
    except Exception as e: con.rollback(); print(t,"err",str(e)[:60])
PY
echo "== which script writes each stale heartbeat"
grep -rl -E "heartbeat" /root/pe-*/*.py /root/pe-logger/*.py /root/bfsp/*.py /root/trading/*.py 2>/dev/null | head -30
echo "== running python daemons"; ps -eo pid,etimes,cmd | grep -E "python3 .*\.py" | grep -v grep | sed -E 's#postgres(ql)?://[^ ]*#<dsn>#g' | awk '{print $1, int($2/60)"min", $4, $5}' | head -40
