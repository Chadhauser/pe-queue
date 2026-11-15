import sys, psycopg2
sys.path.insert(0, '/root/pe-queue/runner')
import creds
c = psycopg2.connect(creds.pg_local())
cur = c.cursor()
cur.execute("SET statement_timeout='300s'")
cur.execute("select mkt, count(*), count(distinct market_id), min(ts), max(ts) from liq_sample group by 1 order by 3 desc")
for r in cur.fetchall():
    print(r)
cur.execute("select sel, minute, ltp, back_px, lay_px, back_sz, lay_sz from liq_sample where mkt ilike '%half%full%' or mkt in ('HTFT','HT_FT') limit 8")
for r in cur.fetchall():
    print(r)
