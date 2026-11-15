import sys, psycopg2
sys.path.insert(0, '/root/pe-queue/runner')
import creds
con = psycopg2.connect(creds.pg_local())
c = con.cursor()
c.execute("SET statement_timeout='300s'; SET work_mem='64MB'")
for t in ('racing_bsp', 'bf_hist_other'):
    c.execute("SELECT column_name,data_type FROM information_schema.columns WHERE table_name=%s ORDER BY ordinal_position", (t,))
    print(t, c.fetchall())
c.execute("SELECT * FROM racing_bsp LIMIT 2")
print(c.fetchall())
c.execute("SELECT count(distinct menu_hint), min(event_dt), max(event_dt), count(*) FROM racing_bsp") if False else None
c.execute("SELECT DISTINCT market_id,event_name,country,market_time FROM bf_hist_other WHERE sport='Horse Racing' AND market_type='WIN' AND market_time>='2026-09-12' AND market_time<'2026-09-13' LIMIT 8")
print(c.fetchall())
