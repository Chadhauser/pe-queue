import sys, psycopg2
sys.path.insert(0, '/root/pe-queue/runner')
import creds
c = psycopg2.connect(creds.pg_local())
cur = c.cursor()
cur.execute("SET statement_timeout='300s'")
cur.execute("""select event_name, count(*) from liq_sample where mkt='HTFT' and minute between 50 and 60 and lay_px is not null
               group by 1 order by 2 desc limit 1""")
ev = cur.fetchone()[0]
print(ev)
cur.execute("""select distinct on (mkt, sel) ts, mkt, sel, minute, ltp, back_px, back_sz, lay_px, lay_sz from liq_sample
               where event_name=%s and mkt in ('HTFT','MO') and minute between 50 and 60 order by mkt, sel, ts""", (ev,))
for r in cur.fetchall():
    print(tuple(str(x) for x in r))
cur.execute("""select minute, count(*), count(distinct ts) from liq_sample where event_name=%s and mkt='MO' and minute between 40 and 56 group by 1 order by 1""", (ev,))
print(cur.fetchall())
cur.execute("""select count(distinct event_name), count(distinct market_id) from liq_sample where mkt='HTFT' and minute>=46 and lay_px is not null""")
print(cur.fetchall())
cur.execute("""select count(*) from (select distinct ts, event_name from liq_sample where mkt='HTFT' and minute>=46) h
               join (select distinct ts, event_name from liq_sample where mkt='MO' and minute>=46) m using (ts, event_name)""")
print('same ts', cur.fetchall())
cur.execute("""select count(*) from (select distinct ts, event_name from liq_sample where mkt='HTFT' and minute>=46) h""")
print('htft ts', cur.fetchall())
