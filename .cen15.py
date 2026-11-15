import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
for nm, dsn in (('railway', creds.pg_railway()),):
    c = psycopg2.connect(dsn); cur = c.cursor()
    cur.execute("SET statement_timeout='120s'")
    cur.execute("select table_name from information_schema.tables where table_name like 'tennis%'")
    ts = [r[0] for r in cur.fetchall()]; print(nm, ts)
    for t in ts:
        cur.execute("select column_name from information_schema.columns where table_name=%s order by ordinal_position", (t,))
        print(t, [r[0] for r in cur.fetchall()])
        cur.execute(f"select count(*) from {t}"); print(cur.fetchone())
    if 'tennis_results_2026' in ts:
        cur.execute("select comment, count(*) from tennis_results_2026 group by 1 order by 2 desc limit 10")
        print(cur.fetchall())
