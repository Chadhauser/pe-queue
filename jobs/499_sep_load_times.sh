#!/bin/bash
set -o pipefail
# 499_sep_load_times (Finder 2026-11-05, for queue item 140): when did Sep and Aug 2026 soccer files arrive, and did goal_timeline change? Tells whether the moved Sep 2026 lines moved because of prices or results. Read only, no prices.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,psycopg2
sys.path.insert(0,'/root/pe-queue/runner'); import creds
con=psycopg2.connect(creds.pg_local()); cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='600s'")
cur.execute("SHOW timezone"); print("db timezone",cur.fetchone()[0])
cur.execute("""select split_part(path,'/',5)||'-'||split_part(path,'/',6) m,date_trunc('hour',loaded_at)::timestamp(0) h,count(*) from bf_hist_other_files where loaded_at>now()-interval '30 hours' and path ilike '%%/2026/%%' group by 1,2 order by 2,1""")
print("== files by path month and hour, last 30 h")
for r in cur.fetchall(): print("  ",r[0],r[1],f"{r[2]:,}")
cur.execute("""select path from bf_hist_other_files order by loaded_at desc limit 2"""); print("== path shape, newest",[r[0][:70] for r in cur.fetchall()])
cur.execute("""select column_name from information_schema.columns where table_name='goal_timeline' order by ordinal_position"""); print("== goal_timeline columns",[r[0] for r in cur.fetchall()])
cur.execute("""select sport,y,m,status,files,loaded,updated::timestamp(0) from bf_hist_months where sport='Soccer' and y=2026 and m>=5 order by m desc"""); print("== bf_hist_months")
for r in cur.fetchall(): print("  ",r)
print("\n== SURVIVORS: not a price test, none")
PY
