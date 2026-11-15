import sys, time
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local()); cur = c.cursor()
cur.execute("SET statement_timeout='300s'")
cur.execute("""select table_name, column_name from information_schema.columns
 where table_name in ('bf_hist_other','bf_hist_result','bf_hist_markets','bf_load_progress') order by table_name, ordinal_position""")
for r in cur.fetchall(): print(r)
cur.execute("""select relname, n_live_tup from pg_stat_user_tables order by n_live_tup desc limit 40""")
for r in cur.fetchall(): print(r)
