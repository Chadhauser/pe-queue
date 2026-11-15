#!/bin/bash
# 588 (Sun 15 Nov 2026, 16:30). Before writing the results backfill: loader_core.py lines 40-100 verbatim (how market_id is built, how
# results rows are made), what raw files are cached per sport in /root/bfdata, and which sport-months have no results.
set -o pipefail
R=/root/pe-queue/reports/loader_parse_2026-11-15.md
{
echo "# loader_core parse, verbatim — $(date -u '+%F %H:%M') UTC (job 588)"; echo; echo '```python'; sed -n '40,100p' /root/pe-hist/loader_core.py | cut -c1-400; echo '```'
echo "## /root/bfdata"; echo '```'; for d in /root/bfdata/*/; do echo "$d: $(find $d -type f | wc -l) files, $(du -sh $d | cut -f1)"; find $d -type f | head -2; done; ls -la /root/bfdata | head; echo '```'
echo "## months by sport and status"; echo '```'
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
c=psycopg2.connect(creds.pg_local(),sslmode='disable').cursor(); c.execute("SET statement_timeout='120s'")
c.execute("select sport, status, count(*), sum(loaded), min(y*100+m), max(y*100+m) from bf_hist_months group by 1,2 order by 1,2"); [print(r) for r in c.fetchall()]
c.execute("select count(*) from bf_hist_other_files"); print("files loaded:",c.fetchone()[0])
c.execute("select split_part(path,'/',1), count(*) from bf_hist_other_files group by 1 order by 2 desc limit 12"); print("files by first path part:",c.fetchall())
c.execute("select path from bf_hist_other_files limit 3"); print("sample paths:",c.fetchall())
PY
echo '```'
} > $R 2>&1
cd /root/pe-queue && git add reports/loader_parse_2026-11-15.md && git commit -q -m "588: loader parse verbatim" && git pull -q --no-rebase --no-edit && git push -q && echo pushed
echo "588 done"
