import sys, time
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local())
cur = c.cursor()
cur.execute("SET statement_timeout='300s'")
cur.execute("select indexname, indexdef from pg_indexes where tablename in ('bf_hist_other','bf_hist_result')")
for r in cur.fetchall():
    print(r)
t0 = time.time()
cur.execute("""select market_type, sel, count(*) from bf_hist_other
 where sport='Soccer' and ts >= '2023-01-14' and ts < '2023-01-16'
   and market_type in ('FIRST_GOAL_SCORER','CORRECT_SCORE','OVER_UNDER_05') and not inplay
 group by 1,2 order by 3 desc limit 40""")
for r in cur.fetchall():
    print(r)
print('secs', round(time.time() - t0, 1))
cur.execute("""select status, count(*) from bf_hist_result where market_type='FIRST_GOAL_SCORER' and sel ilike 'no goal%' group by 1""")
print(cur.fetchall())
