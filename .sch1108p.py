import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local())
cur = c.cursor()
cur.execute("SET statement_timeout='600s'")
cur.execute("select column_name from information_schema.columns where table_name='bf_hist_other_files' order by ordinal_position")
print([r[0] for r in cur.fetchall()])
cur.execute("select column_name from information_schema.columns where table_name='bf_hist_months' order by ordinal_position")
print([r[0] for r in cur.fetchall()])
cur.execute("select * from bf_hist_months order by 1,2 limit 5")
print(cur.fetchall())
cur.execute("select sport, count(*) from bf_hist_months group by 1")
print(cur.fetchall())
