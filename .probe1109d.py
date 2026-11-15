import sys, time, os
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local()); cur = c.cursor()
cur.execute("SET work_mem='64MB'; SET statement_timeout='900s';")
cur.execute("select column_name from information_schema.columns where table_name='bf_hist_other' order by ordinal_position")
print('bf_hist_other', [r[0] for r in cur.fetchall()])
cur.execute("select min(built_at), max(built_at), count(*), count(distinct market_type), sum((n_is>=300)::int) from fair_price_calib_inplay")
print('inplay map', cur.fetchone())
cur.execute("select max(built_at) from fair_price_calib_inplay"); B = cur.fetchone()[0]
cur.execute("select count(*), min(loaded_at), max(loaded_at) from bf_hist_other_files where loaded_at > %s", (B,))
print('files after B', cur.fetchone())
cur.execute("select count(*) from bf_hist_other_files where loaded_at > now() - interval '1 hour'")
print('files last hour', cur.fetchone())
print('job name taken:', os.path.exists('/root/pe-queue/jobs/499_inplay_map_unseen.sh'))
cur.execute("select indexname, indexdef from pg_indexes where tablename in ('bf_hist_other','bf_hist_result')")
for r in cur.fetchall(): print(r)
