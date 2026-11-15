import sys, psycopg2
sys.path.insert(0, '/root/pe-queue/runner'); import creds
con = psycopg2.connect(creds.pg_local()); cur = con.cursor()
cur.execute("SET statement_timeout='600s'")
cur.execute("""SELECT market_type, count(*) FROM bf_hist_result WHERE sport='Soccer' GROUP BY 1 ORDER BY 2 DESC""")
for r in cur.fetchall(): print(r)
cur.execute("""SELECT column_name FROM information_schema.columns WHERE table_name='bf_hist_result'""")
print([r[0] for r in cur.fetchall()])
cur.execute("""SELECT column_name FROM information_schema.columns WHERE table_name='bf_hist_other'""")
print([r[0] for r in cur.fetchall()])
