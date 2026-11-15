import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local())
cur = c.cursor()
cur.execute("SET work_mem='64MB'; SET statement_timeout='600s';")
cur.execute("""select relname, reltuples::bigint from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where relkind in ('r','p') and nspname='public' and reltuples>100000 order by reltuples desc limit 40""")
for r in cur.fetchall():
    print(r)
cur.execute("""select column_name, data_type from information_schema.columns where table_name='bf_hist_other' order by ordinal_position""")
print(cur.fetchall())
