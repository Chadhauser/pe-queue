import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local())
k = c.cursor()
k.execute("SET statement_timeout='120s'")
k.execute("select sport,yr,mo,status,files_done,last_update from bf_hist_months where sport='Soccer' and (yr,mo) in ((2023,7),(2023,8),(2023,9),(2023,6)) order by yr,mo") if False else None
k.execute("select column_name from information_schema.columns where table_name='bf_hist_months'")
print([r[0] for r in k.fetchall()])
k.execute("select relname, pg_size_pretty(pg_total_relation_size(c.oid)), reltuples::bigint from pg_class c join pg_namespace n on n.oid=c.relnamespace where relkind in ('r','p') and nspname='public' and reltuples>1000 order by pg_total_relation_size(c.oid) desc limit 70")
for r in k.fetchall():
    print(r)
k.execute("select mkt, count(*) from (select mkt from bf_hist_other tablesample system(0.02)) s group by 1 order by 2 desc limit 50")
print(k.fetchall())
