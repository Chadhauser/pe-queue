#!/bin/bash
# 132: evidence pass 126 clean (balance £2,034.48, only our £2 bets in the statement, no unknown DB clients) and Betfair password
# changed + updated on the server -> PG bot back to live £2 (Peter: "if I am trading we trade every game we can"). Tennis stays paper.
python3 - <<'PY'
import sys, psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("UPDATE pg_control SET dry_run=false, note=concat(coalesce(note,''),' | LIVE again 22 Oct after breach check 126 clean') WHERE id=1"); print("pg_control.dry_run = false (live £2)")
cur.execute("SELECT enabled, stake, max_daily_loss, max_open, dry_run FROM pg_control WHERE id=1"); print(cur.fetchone())
PY
pkill -f pg_bot.py; sleep 70; pgrep -af pg_bot.py || echo "pg_bot not running — keepalive?"; crontab -l | grep -i pg_bot
