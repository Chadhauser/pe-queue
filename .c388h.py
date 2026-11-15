import re, sys
sys.path.insert(0, '/root/pe-queue/runner')
for l in open('/root/pe-queue/watchman/FINDER_QUEUE.md'):
    m = re.match(r'^(85|94|105|110|123|213|214|221|360|371)\. ', l)
    if m and 'TODO' in l[:12]:
        print(l[:1150].rstrip()); print()
import creds, psycopg2
c = psycopg2.connect(creds.pg_railway(), connect_timeout=20); c.autocommit = True
cur = c.cursor(); cur.execute("SET statement_timeout='120s'")
cur.execute("select * from bf_price_log order by id desc limit 2")
print('bf_price_log', [d[0] for d in cur.description])
for r in cur.fetchall(): print('  ', str(tuple(r))[:300])
cur.execute("select * from cricket_fav_tape limit 2")
print('cricket_fav_tape', [d[0] for d in cur.description])
for r in cur.fetchall(): print('  ', str(tuple(r))[:300])
cur.execute("select column_name from information_schema.columns where table_name='tennis_results_2026'")
print('tennis_results_2026', [r[0] for r in cur.fetchall()])
cur.execute("select min(market_start),max(market_start),count(distinct market_id),count(*) filter (where won),count(bsp),count(*) from racing_results")
print('racing_results', cur.fetchone())
cur.execute("select count(distinct market_id), count(*) filter (where won)::float/count(distinct market_id) from racing_results where market_start>='2026-10-13'")
print('since 13 Oct: markets, winners per market', cur.fetchone())
