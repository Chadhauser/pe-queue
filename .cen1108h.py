import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local()); cur = c.cursor()
cur.execute("SET statement_timeout='900s'")
cur.execute("select column_name from information_schema.columns where table_name='bf_hist_months' order by ordinal_position")
print(cur.fetchall())
cur.execute("select sport, count(*), sum(case when status ilike 'DONE%%' then 1 else 0 end) from bf_hist_months group by 1 order by 1")
for r in cur.fetchall(): print(r)
cur.execute("""with recursive s as (select min(sport) sp from bf_hist_other
 union all select (select min(sport) from bf_hist_other where sport > s.sp) from s where s.sp is not null)
 select sp from s where sp is not null""")
print('bf_hist_other sports', [r[0] for r in cur.fetchall()])
cur.execute("select sport, count(*) from bf_hist_result group by 1")
print(cur.fetchall())
