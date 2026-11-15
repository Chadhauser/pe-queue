import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local()); cur = c.cursor()
cur.execute("SET work_mem='64MB'; SET statement_timeout='900s';")
cur.execute("""select sel, status, count(*) from bf_hist_result where sport='Soccer' and market_type='HALF_TIME_SCORE'
               group by 1,2 order by 3 desc limit 14""")
print(cur.fetchall())
cur.execute("""select sel, count(*) from bf_hist_result where sport='Soccer' and market_type='OVER_UNDER_45' group by 1""")
print(cur.fetchall())
cur.execute("""select market_id, event_id, event_name, market_time from bf_hist_other
               where sport='Soccer' and market_type='OVER_UNDER_35' and market_time >= '2024-03-02' and market_time < '2024-03-03'
               limit 1""")
mid, eid, en, mt = cur.fetchone(); print(en, mt)
cur.execute("""select market_type, sel, ts, ltp, inplay from bf_hist_other where sport='Soccer' and event_id=%s
               and market_type in ('OVER_UNDER_35','HALF_TIME') and ts between %s + interval '35 min' and %s + interval '75 min'
               order by ts""", (eid, mt, mt))
for r in cur.fetchall(): print(r[0], r[1], r[2].strftime('%H:%M:%S'), r[3], r[4])
cur.execute("""select market_type, sel from bf_hist_result where event_id=%s and status='WINNER'""", (eid,))
print(cur.fetchall())
cur.execute("select min(m), max(m) from bf_hist_price")
print('bf_hist_price m', cur.fetchall())
