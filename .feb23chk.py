import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local()); cur = c.cursor()
cur.execute("SET statement_timeout='300s'")
cur.execute("select sport,y,m,status,files,loaded,updated::timestamp(0) from bf_hist_months where sport='Soccer' and y*100+m between 202208 and 202302 order by y,m")
for r in cur.fetchall(): print(r)
cur.execute("select now()::timestamp(0)"); print('now', cur.fetchone())
