import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_railway_remote(), connect_timeout=20); cur = c.cursor(); cur.execute("SET statement_timeout='200s'")
cur.execute("select market_type, menu_hint, event_name, event_dt, selection_name, win_lose, bsp, race_date from bfsp_history where race_date='2025-03-01' limit 4")
for r in cur.fetchall(): print(r)
cur.execute("select market_type, count(*) from bfsp_history where race_date between '2025-03-01' and '2025-03-07' group by 1")
print(cur.fetchall())
