import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local()); cur = c.cursor()
cur.execute("SET statement_timeout='120s'")
cur.execute("select column_name from information_schema.columns where table_name='bf_hist_other_files'")
print([r[0] for r in cur.fetchall()])
cur.execute("select * from bf_hist_other_files limit 2")
print(cur.fetchall())
cur.execute("select table_name from information_schema.tables where table_name ilike '%load%' or table_name ilike '%progress%' or table_name ilike '%month%'")
print(cur.fetchall())
cur.execute("select now()")
print(cur.fetchone())
