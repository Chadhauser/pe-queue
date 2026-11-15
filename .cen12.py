import sys, psycopg2
sys.path.insert(0, '/root/pe-queue/runner')
import creds
con = psycopg2.connect(creds.pg_local())
c = con.cursor()
c.execute("SET statement_timeout='600s'; SET work_mem='64MB'")
c.execute("""SELECT market_type, to_char(market_time,'YYYY-MM') m, count(distinct market_id) n, count(*) r, sum(inplay::int) ip
             FROM bf_hist_other WHERE sport='Soccer' AND market_type IN ('TO_QUALIFY','EXTRA_TIME') GROUP BY 1,2 ORDER BY 1,2""")
for r in c.fetchall():
    print(r)
c.execute("""SELECT sel, count(*), min(ltp), max(ltp), min(event_name) FROM bf_hist_other
             WHERE sport='Soccer' AND market_type='TO_QUALIFY' AND market_time>='2024-02-13' AND market_time<'2024-02-15' GROUP BY 1 ORDER BY 2 DESC LIMIT 12""")
for r in c.fetchall():
    print(r)
c.execute("SELECT column_name FROM information_schema.columns WHERE table_name='bf_hist_result' ORDER BY ordinal_position")
print([r[0] for r in c.fetchall()])
c.execute("SELECT market_type, count(*) FROM bf_hist_result WHERE market_type IN ('TO_QUALIFY','EXTRA_TIME','MATCH_ODDS') GROUP BY 1")
print(c.fetchall())
