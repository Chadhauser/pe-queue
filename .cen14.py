import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local()); cur = c.cursor()
cur.execute("SET work_mem='64MB'; SET statement_timeout='300s'")
cur.execute("""select relname, reltuples::bigint from pg_class where relkind='r' and relnamespace='public'::regnamespace and reltuples>1000 order by 2 desc limit 60""")
for r in cur.fetchall(): print(r)
cur.execute("select column_name, data_type from information_schema.columns where table_name='bf_hist_other' order by ordinal_position")
print(cur.fetchall())
cur.execute("select attname, most_common_vals from pg_stats where tablename='bf_hist_other' and attname in ('sport','market_type','event_type','country')")
for r in cur.fetchall(): print(r[0], str(r[1])[:1200])
