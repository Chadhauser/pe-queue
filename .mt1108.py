import sys, time
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
H = (open('watchman/HYPOTHESES.md').read() + open('watchman/FINDER_QUEUE.md').read()).upper()
c = psycopg2.connect(creds.pg_local()); cur = c.cursor()
cur.execute("SET statement_timeout='300s'; SET work_mem='64MB'")
t = time.time()
cur.execute("""select market_type, count(distinct market_id) from bf_hist_other
 where sport='Soccer' and market_time>='2023-01-14' and market_time<'2023-01-16' group by 1 order by 2 desc""")
for mt, n in cur.fetchall():
    print(f"{mt:40s} {n:6d} ledger mentions {H.count(mt.upper())}")
print(round(time.time() - t), 's')
