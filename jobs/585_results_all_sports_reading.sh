#!/bin/bash
# 585 (Sun 15 Nov 2026, 16:00). The engine can only calibrate sports that have official results, and bf_hist_result holds Soccer only.
# READ: which loader fills bf_hist_result and bf_hist_other, from what files, whether the raw files for other sports carry runner status
# (Betfair historic market definitions do), what is on disk, and what it would take to backfill results for every sport.
# Writes reports/results_all_sports_2026-11-15.md. No change to data.
set -o pipefail
R=/root/pe-queue/reports/results_all_sports_2026-11-15.md
{
echo "# Results coverage by sport — $(date -u '+%F %H:%M') UTC (job 585)"; echo
echo '```'
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
c=psycopg2.connect(creds.pg_local(),sslmode='disable').cursor(); c.execute("SET statement_timeout='900s'")
c.execute("select sport, count(*), count(distinct market_id), min(market_time)::date, max(market_time)::date from bf_hist_result group by 1 order by 2 desc"); print("bf_hist_result by sport:"); [print("  ",r) for r in c.fetchall()]
c.execute("select column_name, data_type from information_schema.columns where table_name='bf_hist_result' order by ordinal_position"); print("bf_hist_result columns:",c.fetchall())
c.execute("select column_name, data_type from information_schema.columns where table_name='bf_hist_other' order by ordinal_position"); print("bf_hist_other columns:",c.fetchall())
c.execute("select sport, market_type, count(distinct market_id) from bf_hist_result group by 1,2 order by 3 desc limit 15"); print("result market types:",c.fetchall())
for t in ('bf_hist_markets','bf_hist_runners','bf_hist_files','bf_hist_meta','hist_files','bf_hist_load_log'):
    try: c.execute(f"select count(*) from {t}"); print(f"{t}: {c.fetchone()[0]} rows")
    except Exception: c.connection.rollback()
c.execute("select table_name, pg_total_relation_size(table_name::regclass)/1e9 from information_schema.tables where table_schema='public' and table_name like 'bf_hist%' order by 2 desc"); print("bf_hist tables GB:",c.fetchall())
PY
echo '```'
echo "## loader code"; echo '```'
grep -rln "bf_hist_result" /root/pe-*/ --include=*.py 2>/dev/null | head; echo ---
for f in $(grep -rln "bf_hist_result" /root/pe-*/ --include=*.py 2>/dev/null | head -3); do echo "### $f"; grep -n "bf_hist_result\|WINNER\|status\|sport\|def \|glob\|\.bz2\|tar" "$f" | head -40 | cut -c1-200; done
echo '```'
echo "## raw files on disk"; echo '```'
for d in /root/pe-hist /root/pe-sports/hist /root/bf_hist /root/betfair_hist /root/pe-data /data; do [ -d "$d" ] && { echo "$d:"; du -sh "$d" 2>/dev/null; find "$d" -maxdepth 3 -type d | head -20; }; done
find / -xdev \( -name "*.bz2" -o -name "ADVANCED*" -o -name "BASIC*" -o -name "PRO*" \) -path "*etfair*" 2>/dev/null | head -10
crontab -l | grep -i "hist\|loader" | cut -c1-200
echo '```'
echo "## loader state"; echo '```'; ls -la --time-style=+%F_%H:%M /root/pe-sports/team/*load* /root/pe-sports/*load* /root/pe-hist/*.log 2>/dev/null | awk '{print $6,$7}' | head; tail -15 /root/pe-sports/team/history_loader.log 2>/dev/null | cut -c1-200; echo '```'
echo "## bot now"; echo '```'; pgrep -fa bookie_v2 | cut -c1-80; tail -3 /root/pe-sports/bookie/bookie_v2.log | cut -c1-160; echo '```'
} > $R 2>&1
cd /root/pe-queue && git add reports/results_all_sports_2026-11-15.md && git commit -q -m "585: results coverage by sport" && git pull -q --no-rebase --no-edit && git push -q && echo pushed
echo "585 done"
