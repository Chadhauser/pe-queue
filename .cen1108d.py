import sys,psycopg2
sys.path.insert(0,'/root/pe-queue/runner'); import creds
con=psycopg2.connect(creds.pg_local()); cur=con.cursor()
cur.execute("SET work_mem='64MB'; SET statement_timeout='600s'")
cur.execute("SELECT sport,market_type,count(DISTINCT market_id) FROM bf_hist_result GROUP BY 1,2 ORDER BY 1,3 DESC")
for r in cur.fetchall(): print(r)
