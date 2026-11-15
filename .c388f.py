import sys, glob, collections
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_railway(), connect_timeout=20); c.autocommit = True
cur = c.cursor()
cur.execute("SET statement_timeout='180s'")
print('jobs naming the logs:')
for p in glob.glob('/root/pe-queue/jobs/*'):
    if p.endswith('.sh'):
        s = open(p, errors='replace').read()
        for t in ('bf_racing_log', 'bf_tennis_log', 'bf_golf_log'):
            if t in s: print(' ', t, p)
print('== racing log, one week of markets, cadence by mins_to_off band')
cur.execute("""select width_bucket(mins_to_off,-15,240,17) b, count(*), count(distinct market_id),
                      count(distinct (market_id,captured_at)) snaps, count(back_size), count(*) filter (where inplay),
                      count(*) filter (where lay_price is null or back_price is null)
               from bf_racing_log where captured_at>='2026-10-20' and captured_at<'2026-10-27' group by 1 order by 1""")
for r in cur.fetchall(): print(' ', r)
print('== one race, snapshot times for the favourite')
cur.execute("""select market_id from bf_racing_log where captured_at>='2026-10-25' and captured_at<'2026-10-26' limit 1""")
m = cur.fetchone()[0]
cur.execute("""select distinct captured_at, mins_to_off, inplay, total_matched from bf_racing_log where market_id=%s order by 1""", (m,))
rows = cur.fetchall(); print(' ', m, len(rows))
for r in rows[:4] + rows[-12:]: print('  ', r[0].strftime('%H:%M:%S'), r[1], r[2], r[3])
print('== rows, markets per week, sizes')
cur.execute("""select date_trunc('week',captured_at)::date, count(*), count(distinct market_id), count(back_size), count(distinct venue)
               from bf_racing_log where id%%50=0 group by 1 order by 1""")
for r in cur.fetchall(): print(' ', r)
print('== venues')
cur.execute("select venue,count(distinct market_id) from bf_racing_log where captured_at>='2026-10-01' and captured_at<'2026-10-15' group by 1 order by 2 desc limit 45")
print(' ', cur.fetchall())
print('== racing_results')
cur.execute("select * from racing_results order by 1 desc limit 2")
print(' ', [d[0] for d in cur.description])
for r in cur.fetchall(): print('  ', str(tuple(r))[:300])
print('== tennis log cadence, one week')
cur.execute("""select inplay, count(*), count(distinct market_id), count(distinct (market_id,captured_at))
               from bf_tennis_log where captured_at>='2026-10-20' and captured_at<'2026-10-27' group by 1""")
print(' ', cur.fetchall())
print('== bf_price_log')
cur.execute("select * from bf_price_log order by id desc limit 2")
print(' ', [d[0] for d in cur.description])
for r in cur.fetchall(): print('  ', str(tuple(r))[:300])
print('== golf_markets')
cur.execute("select market_type,market_year,count(distinct market_id),count(bsp),count(last_price_traded),count(*) from golf_markets group by 1,2 order by 1,2")
print(' ', cur.fetchall()[:20])
