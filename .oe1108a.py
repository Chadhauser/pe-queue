import sys, time, re
Q = open('/root/pe-queue/watchman/FINDER_QUEUE.md').read() + open('/root/pe-queue/watchman/HYPOTHESES.md').read()
for m in re.finditer(r'ODD_OR_EVEN|odd or even|odd/even', Q, re.I):
    print('LEDGER', Q[max(0, m.start()-300):m.start()+200].replace('\n', ' '))
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local())
cur = c.cursor()
cur.execute("SET statement_timeout='1200s'")
t = time.time()
cur.execute("""select date_trunc('month', market_time)::date, count(distinct market_id) from bf_hist_other
 where sport='Soccer' and market_type='ODD_OR_EVEN' group by 1 order by 1""")
print(cur.fetchall())
cur.execute("""select r.status, count(*) from (select distinct market_id from bf_hist_other where sport='Soccer' and market_type='ODD_OR_EVEN') o
 left join bf_hist_result r on r.market_id=o.market_id group by 1""")
print('RES', cur.fetchall(), round(time.time() - t))
