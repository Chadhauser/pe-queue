import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local()); cur = c.cursor()
cur.execute("SET work_mem='64MB'; SET statement_timeout='600s';")
cur.execute("select column_name, data_type from information_schema.columns where table_name='bf_hist_result' order by ordinal_position")
print(cur.fetchall())
cur.execute("""select market_type, count(*), count(distinct market_id), min(market_time)::date, max(market_time)::date
  from bf_hist_result where market_type in ('CORRECT_SCORE','MATCH_ODDS') group by 1""")
for r in cur.fetchall(): print(r)
cur.execute("""select date_trunc('month',market_time)::date, count(distinct market_id) from bf_hist_result
  where market_type='CORRECT_SCORE' and market_time>='2024-08-01' and market_time<'2025-05-01' group by 1 order by 1""")
print(cur.fetchall())
