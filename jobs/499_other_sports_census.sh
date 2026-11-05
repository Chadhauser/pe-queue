#!/bin/bash
set -o pipefail
# 499_other_sports_census (Finder 2026-11-05): counts only, no price is read. Which sports and market types hold official results in bf_hist_result, which months, and how many exactly-one-WINNER markets. Read only.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd
sys.path.insert(0,'/root/pe-queue/runner'); import creds
pd.set_option('display.width',200); pd.set_option('display.max_rows',200)
T0=time.time(); con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='600s'")
print(pd.read_sql("SELECT column_name,data_type FROM information_schema.columns WHERE table_name='bf_hist_result' ORDER BY ordinal_position",con).to_string(index=False))
print("\nofficial results"); print(pd.read_sql("""SELECT sport,market_type,count(*) markets,sum((w=1)::int) one_winner,sum((r=2)::int) two_runner,sum((r=3)::int) three_runner FROM (SELECT sport,market_type,market_id,count(*) r,sum((status='WINNER')::int) w FROM bf_hist_result GROUP BY 1,2,3) x GROUP BY 1,2 HAVING count(*)>=100 ORDER BY 1,3 DESC""",con).to_string(index=False))
print(f"total {time.time()-T0:.0f}s")
PY
