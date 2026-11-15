import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
con = psycopg2.connect(creds.pg_local()); cur = con.cursor()
cur.execute("SET statement_timeout='900s'")
for t in ('bf_hist_other', 'bf_hist_result'):
    cur.execute("select column_name, data_type from information_schema.columns where table_name=%s order by ordinal_position", (t,))
    print(t, cur.fetchall())
cur.execute("select table_name from information_schema.tables where table_schema='public' and (table_name like '%load%' or table_name like '%progress%' or table_name like '%file%') order by 1")
print(cur.fetchall())
# map totals per market type
cur.execute("select market_type, sum(n_is), sum(n_oos), min(built_at) from fair_price_calib group by 1 order by 2 desc")
for r in cur.fetchall():
    print('calib', r)
