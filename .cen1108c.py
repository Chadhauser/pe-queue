import sys, os, glob
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local()); cur = c.cursor()
cur.execute("SET work_mem='64MB'; SET statement_timeout='900s';")
cur.execute("""select market_type, count(distinct market_id), sum((status='WINNER')::int)
               from bf_hist_result where sport='Soccer' group by 1 order by 2 desc""")
rows = cur.fetchall()
texts = {}
for f in glob.glob('/root/pe-queue/jobs/*.sh'):
    try:
        texts[f] = open(f, errors='ignore').read()
    except Exception:
        pass
for mt, n, w in rows:
    k = sum(1 for t in texts.values() if mt in t)
    print(mt, n, w, 'jobs', k)
