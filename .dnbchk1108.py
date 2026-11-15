import sys,psycopg2
sys.path.insert(0,'/root/pe-queue/runner'); import creds
con=psycopg2.connect(creds.pg_local()); cur=con.cursor()
cur.execute("SET work_mem='64MB'; SET statement_timeout='600s'")
cur.execute("""WITH d AS (SELECT market_id, count(*) FILTER (WHERE status='WINNER') w, count(*) n, string_agg(DISTINCT status,',') st FROM bf_hist_result WHERE sport='Soccer' AND market_type='DRAW_NO_BET' GROUP BY 1)
SELECT w,n,st,count(*) FROM d GROUP BY 1,2,3 ORDER BY 4 DESC LIMIT 10""")
for r in cur.fetchall(): print(r)
cur.execute("""SELECT r.event_id,r.sel,r.status FROM bf_hist_result r WHERE sport='Soccer' AND market_type='DRAW_NO_BET' LIMIT 4""")
for r in cur.fetchall(): print(r)
cur.execute("SELECT column_name FROM information_schema.columns WHERE table_name='bf_hist_other' ORDER BY ordinal_position")
print([r[0] for r in cur.fetchall()])
cur.execute("""SELECT date_trunc('month',market_time) m, count(DISTINCT market_id), count(*) FILTER (WHERE inplay) FROM bf_hist_other WHERE sport='Soccer' AND market_type='DRAW_NO_BET' AND market_time>='2024-03-01' AND market_time<'2024-04-01' GROUP BY 1""")
print(cur.fetchall())
