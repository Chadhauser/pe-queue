import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local()); cur = c.cursor()
cur.execute("SET work_mem='64MB'; SET statement_timeout='600s';")
cur.execute("select table_name from information_schema.tables where table_name like 'fair_price%%' order by 1")
tabs = [r[0] for r in cur.fetchall()]
print(tabs)
for t in tabs:
    cur.execute("select column_name, data_type from information_schema.columns where table_name=%s order by ordinal_position", (t,))
    print(t, [r[0] for r in cur.fetchall()])
    cur.execute("select reltuples::bigint from pg_class where relname=%s", (t,))
    print('  est rows', cur.fetchone())
for t in ('fair_price_calib_inplay', 'fair_price_calib_country'):
    if t in tabs:
        cur.execute("select * from %s limit 5" % t)
        for r in cur.fetchall(): print('  ', r)
