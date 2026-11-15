import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local())
k = c.cursor()
k.execute("SET statement_timeout='300s'")
k.execute("select market_type,count(distinct market_id) from bf_hist_result where sport='Soccer' group by 1 order by 2 desc")
print(k.fetchall())
k.execute("select market_type, count(distinct market_id), min(market_time), max(market_time) from bf_hist_other where sport='Soccer' and market_time>='2026-05-01' and (market_type like '%CORNR%') group by 1 order by 2 desc limit 12")
print(k.fetchall())
