import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
con = psycopg2.connect(creds.pg_local()); cur = con.cursor()
cur.execute("SET statement_timeout='900s'")
cur.execute("select column_name, data_type from information_schema.columns where table_name='bf_hist_other_files' order by ordinal_position")
cols = cur.fetchall(); print(cols)
names = [c[0] for c in cols]
tcol = [c for c in names if 'at' in c or 'time' in c or 'ts' in c]
print(tcol)
cur.execute("select * from bf_hist_other_files limit 3")
for r in cur.fetchall(): print(r)
