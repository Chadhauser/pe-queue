#!/bin/bash
# 659 (Thu 19 Nov 2026, 07:00). Read only. Why: watchman says no pre-off bot bets since 18 Nov ~05:00, goal monitor not running,
# v3 recorder caught only 9 markets (17 Nov 19:00-19:45). Report: reports/overnight_659.md
R=/root/pe-queue/reports/overnight_659.md
T=/root/pe-sports/team
{ echo "# 659 — $(date -u '+%F %H:%M') UTC"; echo '```'
echo "== processes"; ps -eo pid,etime,cmd | grep -E 'bookie_v2|small_bites|coherence_paper|book_recorder|v3_recorder|goal|monitor|stream_client|brain' | grep -v grep | cut -c1-160
echo "== bookie_v2 log"; ls -la $T/bookie_v2*.log 2>/dev/null; for f in $(ls -t $T/bookie_v2*.log 2>/dev/null | head -1); do tail -25 $f | cut -c1-220; done
echo "== v3 recorder log"; for f in $(ls -t $T/v3_recorder*.log /root/pe-sports/*/v3_recorder*.log 2>/dev/null | head -1); do tail -12 $f | cut -c1-220; done
echo "== book recorder log"; tail -5 $T/book_recorder.log | cut -c1-200
echo "== crontab (ours)"; crontab -l | grep -E 'v3|bookie|book_rec|coherence|small_bites|goal|monitor' | cut -c1-200
echo "== goal monitor files"; ls -la /root/pe-sports/*/ 2>/dev/null | grep -iE 'goal|monitor' | head -20
python3 - <<'PY'
import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds, psycopg2
c=psycopg2.connect(creds.pg_local(),sslmode='disable').cursor(); c.execute("SET statement_timeout='300s'")
q=lambda s,*a:(c.execute(s,a),c.fetchall())[1]
print("book heartbeat:", q("SELECT * FROM book_heartbeat"))
print("book_snap by day (rows, markets, events):"); [print("  ",r) for r in q("SELECT ts::date, count(*), count(DISTINCT market_id), count(DISTINCT event_id) FROM book_snap GROUP BY 1 ORDER BY 1")]
print("bookie_paper by day/version:"); [print("  ",r) for r in q("SELECT ts::date, version, count(*), count(*) FILTER (WHERE status='settled'), round(coalesce(sum(pnl),0),2) FROM bookie_paper WHERE ts>now()-interval '4 days' GROUP BY 1,2 ORDER BY 1,2")]
print("bookie last bet:", q("SELECT max(ts) FROM bookie_paper"))
print("fair_price_passed rows:", q("SELECT count(*) FROM fair_price_passed"), "blocked:", q("SELECT count(*) FROM fair_price_blocked"))
print("small bites by day:"); [print("  ",r) for r in q("SELECT ts::date, count(*), round(coalesce(sum(pnl),0),2) FROM small_bites_paper WHERE ts>now()-interval '4 days' GROUP BY 1 ORDER BY 1")]
print("v3_snap by day:", q("SELECT ts::date, count(DISTINCT market_id) FROM v3_snap GROUP BY 1 ORDER BY 1"))
print("goal_live_predictions last:", q("SELECT max(created_at) FROM goal_live_predictions") if q("SELECT count(*) FROM information_schema.columns WHERE table_name='goal_live_predictions' AND column_name='created_at'")[0][0] else 'no created_at')
print("goal_alerts last:", q("SELECT max(created_at) FROM goal_alerts") if q("SELECT count(*) FROM information_schema.columns WHERE table_name='goal_alerts' AND column_name='created_at'")[0][0] else 'n/a')
PY
echo '```'; } > $R 2>&1
cd /root/pe-queue && git add $R && git commit -qm "659: overnight check" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
