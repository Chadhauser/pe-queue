import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local())
k = c.cursor()
k.execute("SET statement_timeout='500s'")
k.execute("select indexdef from pg_indexes where tablename='stream_ticks'")
print(k.fetchall())
k.execute("select sport, mkt, inplay, count(*), count(distinct market_id), min(ts_recv), max(ts_recv) from stream_ticks where ts_recv>=now()-interval '36 hours' group by 1,2,3 order by 4 desc limit 20")
for r in k.fetchall(): print(r)
k.execute("select count(*) from stream_ticks")
print(k.fetchone())
