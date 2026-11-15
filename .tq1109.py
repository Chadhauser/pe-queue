import sys,psycopg2
sys.path.insert(0,'/root/pe-queue/runner'); import creds
con=psycopg2.connect(creds.pg_local()); cur=con.cursor()
cur.execute("SET work_mem='64MB'; SET statement_timeout='900s'")
cur.execute("SELECT count(DISTINCT market_id), count(DISTINCT event_id) FROM bf_hist_result WHERE sport='Soccer' AND market_type='TO_QUALIFY'")
print('results TO_QUALIFY markets, events', cur.fetchone())
cur.execute("""SELECT to_char(market_time,'YYYY-MM') mo, count(DISTINCT market_id), count(*), sum(inplay::int)
  FROM bf_hist_other WHERE sport='Soccer' AND market_type='TO_QUALIFY' GROUP BY 1 ORDER BY 1""")
tot=0
for r in cur.fetchall(): print(r); tot+=r[1]
print('total markets',tot)
