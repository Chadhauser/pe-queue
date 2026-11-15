import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local()); cur = c.cursor()
cur.execute("SET statement_timeout='600s'")
cur.execute("select column_name, data_type from information_schema.columns where table_name='bf_hist_other' order by ordinal_position")
print(cur.fetchall())
cur.execute("select column_name from information_schema.columns where table_name='bf_hist_result' order by ordinal_position")
print(cur.fetchall())
cur.execute("select reltuples::bigint from pg_class where relname='bf_hist_other'")
print(cur.fetchall())
cur.execute("select indexdef from pg_indexes where tablename in ('bf_hist_other','bf_hist_result')")
for r in cur.fetchall(): print(r[0])
