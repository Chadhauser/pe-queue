import sys, time
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local())
cur = c.cursor()
cur.execute("SET statement_timeout='600s'")
t0 = time.time()
cur.execute("""explain select market_id, event_id, market_type, market_time, sel, ts, ltp from bf_hist_other
 where sport='Soccer' and market_type=%s and market_time >= '2023-01-09' and market_time < '2023-01-16'
   and not inplay and ts >= market_time - interval '10 minutes' and ts <= market_time
   and sel in ('0 - 0','Under 0.5 Goals')""", ('CORRECT_SCORE',))
for r in cur.fetchall():
    print(r[0])
for mt in ('OVER_UNDER_05', 'CORRECT_SCORE'):
    t0 = time.time()
    cur.execute("""select count(*), count(distinct market_id) from bf_hist_other
     where sport='Soccer' and market_type=%s and market_time >= '2023-01-09' and market_time < '2023-01-16'
       and not inplay and ts >= market_time - interval '10 minutes' and ts <= market_time
       and sel in ('0 - 0','Under 0.5 Goals')""", (mt,))
    print(mt, cur.fetchall(), 'secs', round(time.time() - t0, 1))
