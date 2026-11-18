#!/bin/bash
# 656 (Wed 18 Nov 2026, 06:40). Read only. Morning numbers: the recorder, small bites, the pre-off bot, v3 recorder. Report: reports/morning_656.md
R=/root/pe-queue/reports/morning_656.md
{ echo "# 656 — $(date -u '+%F %H:%M') UTC"; echo '```'
tail -4 /root/pe-sports/team/book_recorder.log | cut -c1-200
python3 - <<'PY'
import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds, psycopg2
c=psycopg2.connect(creds.pg_local(),sslmode='disable').cursor(); c.execute("SET statement_timeout='200s'")
c.execute("SELECT * FROM book_heartbeat"); print("book heartbeat:", c.fetchall())
c.execute("SELECT count(*), count(DISTINCT market_id), count(DISTINCT market_type), count(DISTINCT event_id), min(ts), max(ts) FROM book_snap"); print("book_snap rows/markets/types/events/first/last:", c.fetchone())
c.execute("SELECT pg_size_pretty(pg_total_relation_size('book_snap'))"); print("book_snap size:", c.fetchone())
c.execute("SELECT cell, count(*), count(*) FILTER (WHERE status IN ('closed','stuck')), round(coalesce(sum(pnl),0),2) FROM small_bites_paper GROUP BY 1 ORDER BY 4 DESC"); print("small bites by cell:"); [print("  ",r) for r in c.fetchall()]
c.execute("SELECT count(*), round(coalesce(sum(pnl),0),2) FROM small_bites_paper"); print("small bites total:", c.fetchone())
c.execute("SELECT version, count(*), round(coalesce(sum(pnl),0),2) FROM bookie_paper WHERE status='settled' AND ts>'2026-11-17 09:00' GROUP BY 1"); print("bot settled since v2.2:", c.fetchall())
c.execute("SELECT count(DISTINCT market_id) FROM v3_snap"); print("v3 markets recorded:", c.fetchone())
PY
echo '```'; } > $R 2>&1
cd /root/pe-queue && git add $R && git commit -qm "656: morning status" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
