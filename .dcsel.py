import sys, psycopg2
sys.path.insert(0, '/root/pe-queue/runner')
import creds
c = psycopg2.connect(creds.pg_local())
cur = c.cursor()
cur.execute("""select sel, count(*) from bf_hist_other where sport='Soccer' and market_type='DOUBLE_CHANCE'
               and market_time>='2023-10-07' and market_time<'2023-10-08' group by 1 order by 2 desc limit 8""")
print('tape', cur.fetchall())
cur.execute("""select sel, count(*) from bf_hist_result where sport='Soccer' and market_type='DOUBLE_CHANCE' group by 1 order by 2 desc limit 8""")
print('result', cur.fetchall())
cur.execute("""select sel, count(*) from bf_hist_other where sport='Soccer' and market_type='DOUBLE_CHANCE' and inplay
               and market_time>='2023-10-07' and market_time<'2023-10-08' group by 1 order by 2 desc limit 8""")
print('tape in play', cur.fetchall())
