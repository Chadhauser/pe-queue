#!/bin/bash
# 582 (Sun 15 Nov 2026, 11:10). The first weekly engine run (01:00 UTC) produced 0 RESULT lines for every sport, Soccer included, so
# fair_price_passed is still the 18 football cells from 9 Nov. This job writes the evidence to reports/weekly_engine_2026-11-15.md:
# weekly_engine.log, head and tail of every fairprice_weekly_*.log, how fairprice_v0.py selects its sport (does it read FP_SPORTS?),
# what sports bf_hist_other actually holds, and memory at run time. Fix follows once the cause is read.
set -o pipefail
R=/root/pe-queue/reports/weekly_engine_2026-11-15.md
{
echo "# Weekly engine first run — reading $(date -u '+%F %H:%M') UTC (job 582)"; echo
echo "## weekly_engine.log"; echo '```'; cat /root/pe-sports/team/weekly_engine.log 2>/dev/null | tail -40 | cut -c1-200; echo '```'
echo "## per-sport logs"; for f in /root/pe-sports/team/fairprice_weekly_*.log; do echo "### $(basename $f) ($(wc -l < $f) lines, $(grep -c ^RESULT $f) RESULT)"; echo '```'; head -15 "$f" | cut -c1-200; echo ...; tail -15 "$f" | cut -c1-200; echo '```'; done 2>/dev/null
echo "## how fairprice_v0.py picks its sport"; echo '```'; grep -n "FP_SPORTS\|environ\|sport" /root/pe-sports/team/fairprice_v0.py | head -30 | cut -c1-200; echo '```'
echo "## how it ran on 9 Nov (the run that produced the 18 cells)"; echo '```'; grep -rn "fairprice_v0" /root/pe-queue/jobs/5[0-5]*.sh 2>/dev/null | head -8 | cut -c1-220; ls -la /root/pe-sports/team/fairprice*.log 2>/dev/null | head; echo '```'
echo "## sports in bf_hist_other"; echo '```'
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
c=psycopg2.connect(creds.pg_local(),sslmode='disable').cursor(); c.execute("SET statement_timeout='300s'")
c.execute("select sport, count(*), min(market_time)::date, max(market_time)::date from bf_hist_other where market_time>now()-interval '400 days' group by 1 order by 2 desc"); print(c.fetchall())
c.execute("select sport, count(*) from fair_price_passed group by 1"); print("passed now:",c.fetchall())
c.execute("select count(*) from fair_price_passed_frozen_out"); print("frozen_out rows:",c.fetchone()[0])
PY
echo '```'; echo "## memory now"; free -m | head -2
} > $R 2>&1
cd /root/pe-queue && git add reports/weekly_engine_2026-11-15.md && git commit -q -m "582: weekly engine zero-results reading" && git pull -q --no-edit && git push -q && echo pushed
echo "582 done"
