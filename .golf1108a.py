import sys, time
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local())
cur = c.cursor()
cur.execute("SET statement_timeout='900s'")
cur.execute("select indexdef from pg_indexes where tablename in ('bf_hist_other','bf_hist_result')")
for r in cur.fetchall():
    print(r[0])
cur.execute("select y, m, status, files, loaded from bf_hist_months where sport='Golf' order by y, m")
rows = cur.fetchall()
print('golf months', len(rows), rows[:3], rows[-3:])
t = time.time()
cur.execute("""select market_type, count(distinct market_id), count(*), count(distinct event_id),
  min(market_time), max(market_time), sum(case when inplay then 1 else 0 end)
  from bf_hist_other where sport='Golf' group by 1 order by 2 desc""")
for r in cur.fetchall():
    print(r)
print('secs', round(time.time() - t))
cur.execute("""select market_type, status, count(*) from bf_hist_result where sport='Golf' group by 1,2 order by 1,2""")
for r in cur.fetchall():
    print('RES', r)
