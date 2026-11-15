import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
con = psycopg2.connect(creds.pg_local()); cur = con.cursor()
cur.execute("SET statement_timeout='1200s'; SET work_mem='128MB'")
cur.execute("select min(built_at), max(built_at) from fair_price_calib")
b0, b1 = cur.fetchone(); print('calib built', b0, b1)
cur.execute("select now()")
print('now', cur.fetchone())
cur.execute("""
select split_part(path,'/',5) yr, split_part(path,'/',6) mon, count(*) files,
       min(loaded_at), max(loaded_at), sum((loaded_at > %s)::int) after_build
from bf_hist_other_files where loaded_at > %s::timestamptz - interval '30 hours'
group by 1,2 order by 4""", (b1, b1))
for r in cur.fetchall(): print(r)
