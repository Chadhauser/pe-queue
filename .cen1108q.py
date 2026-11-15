import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local()); cur = c.cursor()
cur.execute("SET statement_timeout='600s'")
cur.execute("""select sport, market_type, count(distinct market_id), min(settled_time)::date, max(settled_time)::date
 from bf_hist_result group by 1,2 having count(distinct market_id) > 300 order by 1, 3 desc""")
for r in cur.fetchall(): print(r)
