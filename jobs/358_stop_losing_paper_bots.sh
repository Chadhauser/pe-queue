#!/bin/bash
# 358: DEAD WEIGHT OFF (audit items 6 and 7). Late-Over dry bot: 123 trades since 24 Oct, -£34 on £250 (-£1.40/£10).
# Pre-off scalper: loses the spread both ways (Finder item 0c). Both are stopped: keepalive killed, cron lines removed,
# a STOPPED marker written so the Watchman does not restart them. Recorders (liq, stream, ip, player) are untouched.
set -o pipefail
echo "== before"; pgrep -af "late_over|preoff_scalp" | sed 's/postgres[^ ]*/<dsn>/g'
( crontab -l 2>/dev/null | grep -v -E "preoff_scalp|late_over" ) | crontab -
pkill -f keepalive_preoff_scalp.sh 2>/dev/null; pkill -f watchdog_preoff_scalp.sh 2>/dev/null; pkill -f preoff_scalp_paper.py 2>/dev/null
pkill -f late_over_paper.py 2>/dev/null; pkill -f "keepalive.*late_over" 2>/dev/null
for d in /root/pe-race /root/pe-xg; do [ -d $d ] && echo "STOPPED $(date -u +%F) by jobs/358: negative paper line, do not restart (audit 5 Nov)" > $d/STOPPED; done
sleep 3; echo "== after"; pgrep -af "late_over|preoff_scalp" | sed 's/postgres[^ ]*/<dsn>/g' || echo "none running"
echo "== cron now"; crontab -l | grep -E "late_over|preoff" || echo "no cron entries"
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
c=psycopg2.connect(creds.pg_railway(), sslmode='require'); c.autocommit=True; k=c.cursor()
k.execute("CREATE TABLE IF NOT EXISTS bot_status (bot TEXT PRIMARY KEY, status TEXT, since TIMESTAMPTZ, reason TEXT)")
for b,r in (('late_over_paper','-£1.40/£10 over 123 dry trades 24 Oct-5 Nov'),('preoff_scalp_paper','loses the spread both ways, Finder item 0c 4 Nov')):
    k.execute("INSERT INTO bot_status VALUES (%s,'STOPPED',now(),%s) ON CONFLICT (bot) DO UPDATE SET status='STOPPED', since=now(), reason=EXCLUDED.reason",(b,r))
k.execute("select * from bot_status"); print(k.fetchall())
PY
