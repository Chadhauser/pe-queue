#!/bin/bash
# 631 (Tue 17 Nov 2026, 07:00). Read only. 630: goal_alerts inserts work (boot test OK, sequences fine) yet no alert row since 7 Nov.
# Show the code path from "fired" to the INSERT (monitor_ht.py 200-340) and how fresh the real-price table it reads is.
R=/root/pe-queue/reports/goal_insert_631.md
F=/root/pe-brain/repo/brain/monitor_ht.py
{ echo "# 631 — $(date -u '+%F %H:%M') UTC"; echo '```python'; sed -n 180,340p $F; echo '```'
echo "## fired lines with the nearest timestamps in the log"; echo '```'; grep -nE "fired=[1-9]" /root/pe-brain/monitor_ht.log | tail -5; wc -l < /root/pe-brain/monitor_ht.log; grep -nE "20[0-9]{2}-[0-9]{2}-[0-9]{2}" /root/pe-brain/monitor_ht.log | tail -3; echo '```'
echo "## tables named in that code, freshness"; echo '```'
for t in $(sed -n 180,340p $F | grep -oE "FROM [a-z_]+" | awk '{print $2}' | sort -u); do
  python3 - "$t" <<'PY'
import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds, psycopg2
t=sys.argv[1]; c=psycopg2.connect(creds.pg_local(),sslmode='disable').cursor(); c.execute("SET statement_timeout='60s'")
c.execute("SELECT column_name FROM information_schema.columns WHERE table_name=%s AND data_type LIKE 'timestamp%%' ORDER BY ordinal_position",(t,)); tc=[r[0] for r in c.fetchall()]
if not tc: print(t,"no timestamp column / not a table"); sys.exit()
c.execute(f'SELECT max("{tc[0]}") FROM "{t}"'); print(t, tc[0], "last", c.fetchone()[0])
PY
done; echo '```'; } > $R 2>&1
cd /root/pe-queue && git add $R && git commit -qm "631: goal alert insert path" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
