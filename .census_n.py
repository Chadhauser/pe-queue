import sys
sys.path.insert(0, 'runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local())
c.autocommit = True
k = c.cursor()
k.execute("set statement_timeout='120s'")
k.execute("select column_name, data_type from information_schema.columns where table_name='bf_hist_months' order by ordinal_position")
print('months cols', [r[0] for r in k.fetchall()])
k.execute("select * from bf_hist_months where sport='Soccer' and (y,m) in ((2026,6),(2026,7),(2026,8),(2026,9),(2023,5),(2023,4)) order by 1,2,3")
for r in k.fetchall():
    print(str(r)[:140])
for t in ['bf_hist_other', 'bf_hist_result', 'racing_bsp', 'af_fixtures']:
    k.execute("select column_name from information_schema.columns where table_name=%s order by ordinal_position", (t,))
    print(t, [r[0] for r in k.fetchall()])
k.execute("select relname, reltuples::bigint from pg_class where relkind='r' and relnamespace='public'::regnamespace order by reltuples desc limit 45")
print([(a, b) for a, b in k.fetchall()])
