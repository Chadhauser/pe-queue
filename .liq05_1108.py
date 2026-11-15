import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
for nm, dsn in (('local', creds.pg_local()), ('railway', creds.pg_railway())):
    try:
        c = psycopg2.connect(dsn, connect_timeout=20); cur = c.cursor()
        cur.execute("SET statement_timeout='90s'")
        cur.execute("select to_regclass('liq_sample')")
        if cur.fetchone()[0] is None: print(nm, 'no liq_sample'); continue
        cur.execute("select column_name from information_schema.columns where table_name='liq_sample'")
        cols = [r[0] for r in cur.fetchall()]; print(nm, 'cols', cols)
        mc = [x for x in cols if x in ('mkt', 'market', 'mtype', 'market_name', 'mkt_type')]
        if mc:
            cur.execute(f"select {mc[0]}, count(*) from liq_sample where ts>now()-interval '2 days' group by 1 order by 2 desc limit 40")
            print(nm, cur.fetchall())
    except Exception as e:
        print(nm, 'error', type(e).__name__, str(e)[:160])
