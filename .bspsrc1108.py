import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
for name, dsn in (('local', creds.pg_local()), ('railway', creds.pg_railway_remote())):
    try:
        c = psycopg2.connect(dsn, connect_timeout=20); cur = c.cursor(); cur.execute("SET statement_timeout='60s'")
        cur.execute("select table_name, column_name from information_schema.columns where table_schema='public' and (column_name ilike '%bsp%' or column_name ilike 'sp_%' or column_name ilike '%starting%') order by 1")
        print(name, cur.fetchall())
        cur.execute("select min(event_dt), max(event_dt), count(*) from racing_bsp where market='win'") if name == 'local' else None
        if name == 'local': print('racing_bsp win', cur.fetchall())
        c.close()
    except Exception as e:
        print(name, 'error', type(e).__name__, str(e)[:120])
