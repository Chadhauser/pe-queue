#!/bin/bash
# 342: RECORDER WIRING (report only, short). For each live recorder/paper bot on this box: which tables it INSERTs into and
# how it obtains its DSN, so the repoint to the local Postgres (job 343) edits exactly the right lines. No values printed.
for f in /root/pe-liq/liq_recorder.py /root/pe-ip/ip_recorder.py /root/pe-stream/stream_client.py /root/pe-xx/xx_recorder.py /root/pe-race/preoff_scalp_paper.py /root/pe-coach/coach_tape.py /root/pe-logger/stats_collector.py /root/pe-logger/server_price_logger.py /root/pe-logger/racing_price_logger.py /root/pe-logger/tennis_price_logger.py /root/pe-xg/late_over_paper.py; do
  [ -f "$f" ] || { echo "MISSING $f"; continue; }
  echo "-- $f"
  grep -n -oE "INSERT INTO [a-z_]+|DELETE FROM [a-z_]+[^;]{0,60}|psycopg2\.connect\([^)]{0,60}|from bot_core import [A-Za-z_, ]+|os\.environ(\.get)?\(['\"][A-Z_]+|os\.getenv\(['\"][A-Z_]+" "$f" | sed -E 's#postgres(ql)?://[^ "'"'"')]*#<dsn>#g' | sort | uniq -c | sort -rn | head -12
done
echo "== pe-liq keepalive"; cat /root/pe-liq/keepalive.sh 2>/dev/null | head -20
echo "== how bot_core defines DB (name only)"; grep -n -E "^DB\s*=|DATABASE_URL" /root/pe-bot/bot_core.py | sed -E 's#postgres(ql)?://[^ "'"'"']*#<dsn>#g' | head -3
echo "== processes writing now"; ps -eo pid,etimes,cmd | grep -E "python3 .*(recorder|logger|stream|client|paper|tape|collector|bot)\.py" | grep -v grep | sed -E 's#postgres(ql)?://[^ ]*#<dsn>#g' | head -20
exit 0
