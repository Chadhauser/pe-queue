import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local()); cur = c.cursor()
cur.execute("SET work_mem='64MB'; SET statement_timeout='600s'")
for sport in ('Horse Racing', 'Greyhound Racing'):
    cur.execute("""select country,market_type,count(distinct market_id),count(*),count(*) filter (where inplay)
                   from bf_hist_other where sport=%s and market_time>='2026-05-01' and market_time<'2026-06-01'
                   group by 1,2 order by 3 desc limit 30""", (sport,))
    print(sport, 'May 2026')
    for r in cur.fetchall(): print(' ', r)
cur.execute("select sport,market_type,count(distinct market_id) from bf_hist_result group by 1,2 order by 1,3 desc")
rows = cur.fetchall()
seen = {}
for r in rows:
    seen[r[0]] = seen.get(r[0], 0) + 1
    if seen[r[0]] <= 8: print(r)
cur.execute("""select market_id,event_name,country,count(distinct sel),min(ts),max(ts) from bf_hist_other
               where sport='Horse Racing' and market_type='WIN' and market_time>='2026-05-02' and market_time<'2026-05-03' and country<>'GB' and country<>'IE'
               group by 1,2,3 limit 12""")
for r in cur.fetchall(): print(r)
cur.execute("select column_name from information_schema.columns where table_name='racing_results'")
print('racing_results cols local', cur.fetchall())
cur.execute("select column_name from information_schema.columns where table_name='racing_bsp'")
print('racing_bsp cols local', [r[0] for r in cur.fetchall()])
