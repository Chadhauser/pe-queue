#!/bin/bash
# 338: MIGRATION RECON (report only). What is on Railway (sizes, versions), which recorders on this box write which tape
# tables and how they get their DSN, so the repoint job can be exact. Nothing is changed.
set -o pipefail
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
con=psycopg2.connect(creds.pg_railway(), sslmode='require', connect_timeout=20); con.autocommit=True; cur=con.cursor(); cur.execute("SET statement_timeout='300s'")
cur.execute("show server_version"); print("railway server:",cur.fetchone()[0])
cur.execute("""select relname, reltuples::bigint, pg_size_pretty(pg_total_relation_size(c.oid)), pg_total_relation_size(c.oid)
 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and relkind='r' order by 4 desc""")
tot=0; print("\n== tables (est rows | size)")
for r in cur.fetchall(): tot+=r[3]; print(f"{r[0]:32s} {r[1]:>14,} {r[2]:>9s}")
print("TOTAL", round(tot/1e9,1),"GB")
cur.execute("select relname from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and relkind in ('v','m')"); print("views:",[r[0] for r in cur.fetchall()])
cur.execute("select event_object_table, trigger_name from information_schema.triggers where trigger_schema='public'"); print("triggers:",cur.fetchall())
cur.execute("select extname from pg_extension"); print("extensions:",[r[0] for r in cur.fetchall()])
PY
echo "== recorders on this box and how they connect"
for f in /root/pe-liq/liq_recorder.py /root/pe-ip/ip_recorder.py /root/pe-stream/stream_client.py /root/pe-xx/xx_recorder.py /root/pe-race/preoff_scalp_paper.py /root/pe-coach/coach_tape.py /root/pe-logger/stats_collector.py; do
  [ -f "$f" ] || { echo "MISSING $f"; continue; }
  echo "-- $f"; grep -n -E "psycopg2.connect|bot_core import|DATABASE_URL|DB_URL|dsn|sslmode|INSERT INTO [a-z_]+" "$f" | sed 's/postgres:\/\/[^ "'"'"']*/<dsn>/g' | head -12
done
echo "== who else writes the tape tables (any file under /root)"
grep -rl -E "INSERT INTO (ip_tape|liq_sample|stream_ticks)" /root --include=*.py 2>/dev/null | grep -v pe-queue/jobs | head
echo "== pruners anywhere (delete/truncate/retention on tape tables)"
grep -rn -iE "(delete from|truncate)\s+(ip_tape|liq_sample|stream_ticks)|retention|interval '[0-9]+ day" /root --include=*.py --include=*.sh --include=*.sql 2>/dev/null | grep -v pe-queue/jobs | grep -v "\.bak" | head -20
echo "== crontab"; crontab -l | grep -v "^#" | head -40
echo "== systemd units of ours"; systemctl list-units --type=service --no-pager 2>/dev/null | grep -iE "pe-|liq|tape|stream|recorder" | head
