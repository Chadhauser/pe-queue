import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local())
cur = c.cursor()
cur.execute("SET statement_timeout='600s'")
cur.execute("""select coalesce(substring(selection_name from '\\(([A-Z]{2,3})\\)\\s*$'), 'NONE') sfx, country, count(*), count(distinct event_id)
 from racing_bsp where market='win' group by 1,2 order by 3 desc limit 30""")
for r in cur.fetchall():
    print(r)
cur.execute("select selection_name, event_name, menu_hint from racing_bsp where market='win' order by random() limit 12")
for r in cur.fetchall():
    print(r)
cur.execute("select min(event_dt), max(event_dt), count(distinct event_id) from racing_bsp where market='win'")
print(cur.fetchall())
