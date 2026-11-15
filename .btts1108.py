import re, sys
sys.path.insert(0, '/root/pe-queue/runner'); import creds, psycopg2
n = [int(m.group(1)) for l in open('/root/pe-queue/watchman/FINDER_QUEUE.md') for m in [re.match(r'^(\d+)\. ', l)] if m]
print('max item', max(n))
con = psycopg2.connect(creds.pg_local()); cur = con.cursor()
cur.execute("SET work_mem='64MB'; SET statement_timeout='600s'")
# coverage of in-play BTTS prints on the local tape: one month, cheap
cur.execute("""SELECT market_type, count(DISTINCT market_id), count(*) FILTER (WHERE inplay)
               FROM bf_hist_other WHERE sport='Soccer' AND market_time>='2023-03-01' AND market_time<'2023-03-08'
               AND market_type IN ('BOTH_TEAMS_TO_SCORE','MATCH_ODDS','OVER_UNDER_05','OVER_UNDER_15') GROUP BY 1""")
for r in cur.fetchall(): print(r)
cur.execute("""SELECT DISTINCT sel FROM bf_hist_other WHERE sport='Soccer' AND market_type='BOTH_TEAMS_TO_SCORE'
               AND market_time>='2023-03-01' AND market_time<'2023-03-02' LIMIT 5""")
print(cur.fetchall())
