import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local())
cur = c.cursor()
cur.execute("SET statement_timeout='300s'")
cur.execute("select column_name, data_type from information_schema.columns where table_name='bf_hist_other' order by ordinal_position")
print(cur.fetchall())
cur.execute("select column_name, data_type from information_schema.columns where table_name='bf_hist_result' order by ordinal_position")
print(cur.fetchall())
cur.execute("select market_type, count(*) from bf_hist_result group by 1 order by 2 desc")
for r in cur.fetchall():
    print(r)
t = open('/root/pe-queue/watchman/HYPOTHESES.md').read().upper()
cur.execute("select market_type, count(*) from bf_hist_result group by 1 order by 2 desc")
print('-- market types and how often HYPOTHESES names them')
for mt, n in cur.fetchall():
    print(mt, n, t.count(mt.upper()))
