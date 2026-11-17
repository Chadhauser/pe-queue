#!/bin/bash
# 644 (Tue 17 Nov 2026, 14:05). Read only. Midday numbers: small-bites forward paper by cell, bot paper by version today, and why the
# stream tape was silent 06:33-09:08 UTC this morning (stream.log around the gap). Report: reports/midday_644.md
R=/root/pe-queue/reports/midday_644.md
{ echo "# 644 — $(date -u '+%F %H:%M') UTC"; echo '```'
python3 - <<'PY'
import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds, psycopg2
c=psycopg2.connect(creds.pg_local(),sslmode='disable').cursor()
c.execute("""SELECT cell, liq, count(*), count(*) FILTER (WHERE status='closed'), count(*) FILTER (WHERE status='stuck'), count(*) FILTER (WHERE status='open'),
             round(coalesce(sum(pnl),0),2), round(coalesce(sum(pnl) FILTER (WHERE pnl>0),0),2) FROM small_bites_paper GROUP BY 1,2 ORDER BY 1,2""")
print("small bites (cell, liq, trades, closed, stuck, open, pnl, gross wins):"); [print("  ",r) for r in c.fetchall()]
c.execute("SELECT count(*), round(coalesce(sum(pnl),0),2), min(created), max(created) FROM small_bites_paper"); print("small bites total:", c.fetchone())
c.execute("""SELECT version, status, count(*), round(coalesce(sum(pnl),0),2) FROM bookie_paper WHERE ts>now()-interval '24 hours' GROUP BY 1,2 ORDER BY 1,2"""); print("bot last 24h:", c.fetchall())
c.execute("""SELECT version, count(*), round(coalesce(sum(pnl),0),2) FROM bookie_paper WHERE status='settled' AND ts>'2026-11-01' GROUP BY 1 ORDER BY 1"""); print("bot settled this month by version:", c.fetchall())
PY
L=$(ls /root/pe-stream/stream*.log 2>/dev/null | head -1); echo "--- $L around the gap"
grep -nE "06:2[0-9]|06:3[0-9]|09:0[0-9]" "$L" | grep -viE "tick|rows" | head -30 | cut -c1-220
grep -nE "TIMEOUT|auth|reconnect|Error|Exception|close" "$L" | tail -15 | cut -c1-220
echo '```'; } > $R 2>&1
cd /root/pe-queue && git add $R && git commit -qm "644: midday status" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
