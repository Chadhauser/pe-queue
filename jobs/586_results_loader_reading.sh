#!/bin/bash
# 586 (Sun 15 Nov 2026, 16:05). 585's SQL used a column bf_hist_result does not have, and its grep listed the wrong repo. Read the real
# loader (/root/pe-hist/loader.py, loader_adv.py): how it fills bf_hist_result, why only Soccer, and what the raw source carries.
set -o pipefail
R=/root/pe-queue/reports/results_all_sports_2026-11-15.md
{
echo "# Results coverage by sport — $(date -u '+%F %H:%M') UTC (job 586)"; echo; echo '```'
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
c=psycopg2.connect(creds.pg_local(),sslmode='disable').cursor(); c.execute("SET statement_timeout='900s'")
c.execute("select column_name from information_schema.columns where table_name='bf_hist_result' order by ordinal_position"); print("bf_hist_result columns:",[r[0] for r in c.fetchall()])
c.execute("select sport, count(*), count(distinct market_id) from bf_hist_result group by 1 order by 2 desc"); print("bf_hist_result by sport:",c.fetchall())
c.execute("select sport, count(distinct market_id) from bf_hist_other where market_time<now()-interval '2 days' group by 1 order by 2 desc"); print("bf_hist_other settled-age markets by sport:",c.fetchall())
c.execute("select sport, market_type, count(distinct market_id) from bf_hist_result group by 1,2 order by 3 desc limit 12"); print("result types:",c.fetchall())
c.execute("select table_name, round(pg_total_relation_size(table_name::regclass)/1e9,1) from information_schema.tables where table_schema='public' and table_name like 'bf_hist%' order by 2 desc"); print("bf_hist tables GB:",c.fetchall())
PY
echo '```'
echo "## /root/pe-hist"; echo '```'; ls -la --time-style=+%F_%H:%M /root/pe-hist | awk '{print $5,$6,$7}' | head -30; echo '```'
for f in /root/pe-hist/loader.py /root/pe-hist/loader_adv.py; do [ -f $f ] && { echo "### $f ($(wc -l < $f) lines) — header + every line touching results, sport, files, status"; echo '```'; head -25 $f | cut -c1-200; echo ...; grep -n "bf_hist_result\|WINNER\|'status'\|\"status\"\|sport\|SPORT\|glob\|listdir\|\.bz2\|tar\|EVENT_TYPE\|event_type\|def " $f | grep -v "^[0-9]*:#" | head -60 | cut -c1-220; echo '```'; }; done
echo "## loader logs"; echo '```'; tail -12 /root/pe-hist/loader.log | cut -c1-200; echo ---; tail -12 /root/pe-hist/loader_adv.log | cut -c1-200; echo '```'
echo "## keepalive"; echo '```'; cat /root/pe-hist/keepalive_hist.sh | head -20 | cut -c1-200; echo '```'
echo "## raw files"; echo '```'; for d in /root/pe-hist/data /root/pe-hist/raw /root/pe-hist/files /root/bfdata /root/pe-sports/hist; do [ -d $d ] && { echo $d; du -sh $d; ls $d | head -8; }; done; grep -rho "/root/[a-zA-Z0-9_/.-]*" /root/pe-hist/loader.py /root/pe-hist/loader_adv.py 2>/dev/null | sort -u | head -10; echo '```'
} > $R 2>&1
cd /root/pe-queue && git add reports/results_all_sports_2026-11-15.md && git commit -q -m "586: results loader reading" && git pull -q --no-rebase --no-edit && git push -q && echo pushed
echo "586 done"
