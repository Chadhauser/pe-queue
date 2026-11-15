import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local())
cur = c.cursor()
cur.execute("select column_name from information_schema.columns where table_name='bf_hist_months' order by ordinal_position")
cols = [r[0] for r in cur.fetchall()]
cur.execute("select * from bf_hist_months where sport='Soccer' and ((y=2022 and m in (8,9,10)))" if 'y' in cols else "select * from bf_hist_months where sport='Soccer' limit 0")
print(cols)
for r in cur.fetchall():
    print(r)
cur.execute("select now()")
print(cur.fetchall())
