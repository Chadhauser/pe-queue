import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local()); cur = c.cursor()
cur.execute("SET statement_timeout='120s'")
cur.execute("select y,m,status,files,loaded,updated::timestamp(0) from bf_hist_months where sport='Soccer' and (y,m)<(2023,4) order by y desc,m desc limit 8")
for r in cur.fetchall(): print(*r)
