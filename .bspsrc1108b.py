import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_railway_remote(), connect_timeout=20); cur = c.cursor(); cur.execute("SET statement_timeout='120s'")
for t in ('bfsp_history', 'racing_results'):
    cur.execute("select column_name, data_type from information_schema.columns where table_name=%s order by ordinal_position", (t,))
    cols = cur.fetchall(); print(t, cols)
    cur.execute("select reltuples::bigint from pg_class where relname=%s", (t,)); print(' est rows', cur.fetchall())
    dcol = next((n for n, ty in cols if 'time' in ty or ty == 'date'), None)
    if dcol:
        cur.execute(f"select min({dcol}), max({dcol}) from {t}"); print(' range', dcol, cur.fetchall())
        cur.execute(f"select date_trunc('month',{dcol})::date m, count(*) from {t} where {dcol}>='2024-08-01' group by 1 order by 1"); print(' by month', cur.fetchall())
