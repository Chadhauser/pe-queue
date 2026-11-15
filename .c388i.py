import sys, glob, re
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_railway(), connect_timeout=20); c.autocommit = True
cur = c.cursor(); cur.execute("SET statement_timeout='200s'")
for d in ('2026-08-29', '2026-09-26', '2026-10-17', '2026-10-31'):
    cur.execute("""select count(*),count(distinct market_id),count(distinct captured_at),count(back_size) from bf_price_log where captured_at>=%s and captured_at<%s::timestamptz + interval '1 hour'""", (d + ' 14:00', d + ' 14:00'))
    print(' Sat 14-15 UTC', d, cur.fetchone())
cur.execute("""select regexp_replace(market_name,'^.* - ','') t,count(*),count(distinct market_id),count(distinct captured_at)
               from bf_price_log where captured_at>='2026-10-31 14:00' and captured_at<'2026-10-31 15:00' group by 1 order by 2 desc limit 12""")
for r in cur.fetchall(): print(' mix', r)
cur.execute("""select market_id,market_name from bf_price_log where captured_at>='2026-10-31 15:00' and captured_at<'2026-10-31 15:01' and market_name ~ 'Over/Under 2.5' limit 1""")
row = cur.fetchone()
if row:
    m = row[0]
    cur.execute("select distinct captured_at from bf_price_log where market_id=%s and captured_at>='2026-10-29' order by 1", (m,))
    rows = [r[0] for r in cur.fetchall()]; print(' one market', row[1], len(rows), rows[0], rows[-1])
    gaps = sorted((b-a).total_seconds() for a, b in zip(rows, rows[1:]))
    print(' gap median', gaps[len(gaps)//2], 'p90', gaps[int(len(gaps)*.9)], 'max', gaps[-1])
print(' jobs:', [p.split('/')[-1] for p in glob.glob('/root/pe-queue/jobs/*.sh') if 'bf_price_log' in open(p, errors='replace').read()])
L = psycopg2.connect(creds.pg_local()); lc = L.cursor()
lc.execute("select event_dt::date,count(distinct event_id) from racing_bsp where lower(market)='win' and event_dt>='2026-10-08' group by 1 order by 1")
print(' racing_bsp win races by day', [(str(a)[5:], b) for a, b in lc.fetchall()])
