import sys, time, re
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local())
cur = c.cursor()
cur.execute("SET statement_timeout='900s'")
cur.execute("select sport, status, count(*), min(y*100+m), max(y*100+m) from bf_hist_months group by 1,2 order by 1,2")
for r in cur.fetchall():
    print(r)
t = time.time()
cur.execute("""select market_type, count(distinct market_id), count(*), sum(case when inplay then 1 else 0 end)
 from bf_hist_other where sport='Soccer' and market_time >= '2026-09-01' and market_time < '2026-09-08'
 group by 1 order by 2 desc""")
types = cur.fetchall()
print('secs', round(time.time() - t))
Q = open('/root/pe-queue/watchman/FINDER_QUEUE.md').read() + open('/root/pe-queue/watchman/HYPOTHESES.md').read()
import glob
J = ''.join(open(f, errors='ignore').read() for f in glob.glob('/root/pe-queue/jobs/*.sh'))
for mt, nm, nr, ni in types:
    print(mt, nm, nr, ni, 'ledger', len(re.findall(re.escape(mt), Q)), 'jobs', len(re.findall(re.escape(mt), J)))
