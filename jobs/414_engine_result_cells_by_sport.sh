#!/bin/bash
# 581 (Sun 15 Nov 2026, 10:15). Peter: "why only one thing and not 7000 across all sports?" Read last night's weekly engine run (first
# run, Sunday 01:00 UTC): how many cells were TESTED per sport, how many PASSED the Verifier, and what the bot's universe is now.
# 414 (watchman fix of 581): last query read bookie_paper.sport, which does not exist (UndefinedColumn, heredoc line 8); grouped by mkt instead
set -o pipefail
echo "== weekly_engine.log =="; tail -30 /root/pe-sports/team/weekly_engine.log 2>/dev/null | cut -c1-200
echo "== RESULT lines per sport (cells tested) =="; for f in /root/pe-sports/team/fairprice_weekly_*.log; do echo "$(basename $f): $(grep -c ^RESULT $f) tested, $(grep -c 'PASS' $f) pass-marked"; done 2>/dev/null
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
c=psycopg2.connect(creds.pg_local(),sslmode='disable').cursor()
c.execute("select sport, count(*) from fair_price_passed group by 1 order by 2 desc"); print("PASSED cells by sport now:",c.fetchall())
c.execute("select count(*) from fair_price_passed"); print("total passed:",c.fetchone()[0])
for t in ('fair_price_cells','fair_price_results','fairprice_cells'):
    try: c.execute(f"select sport,count(*) from {t} group by 1 order by 2 desc"); print(f"TESTED cells in {t}:",c.fetchall()); break
    except Exception as e: c.connection.rollback()
c.execute("select coalesce(mkt,'?'), count(*) from bookie_paper where version='v2' and fill_kind='taker' and ts>now()-interval '24 hours' group by 1"); print("bot bets last 24h by market type (bookie_paper has no sport column):",c.fetchall())
PY
echo "414 done"
