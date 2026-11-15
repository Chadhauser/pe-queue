import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local()); cur = c.cursor()
cur.execute("SET statement_timeout='600s'")
cur.execute("select sport, market_type, count(distinct market_id) n from bf_hist_result group by 1,2 order by 3 desc")
q = open('/root/pe-queue/watchman/FINDER_QUEUE.md').read().upper()
for s, m, n in cur.fetchall():
    if n >= 2000:
        print(s, m, n, 'queue mentions', q.count(m.upper()))
