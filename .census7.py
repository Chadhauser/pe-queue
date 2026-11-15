import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local())
k = c.cursor()
k.execute("SET statement_timeout='300s'")
k.execute("select y,m,status,files,loaded,updated from bf_hist_months where sport='Soccer' and y=2023 order by m")
print(k.fetchall())
k.execute("select column_name from information_schema.columns where table_name='bf_hist_other'")
print([r[0] for r in k.fetchall()])
k.execute("select column_name from information_schema.columns where table_name='bf_hist_result'")
print([r[0] for r in k.fetchall()])
k.execute("""select f.season, count(distinct f.fixture_id), count(distinct e.fixture_id),
   count(distinct e.fixture_id) filter (where lower(e.type)='subst'),
   count(distinct e.fixture_id) filter (where e.type='Card'),
   count(*) filter (where e.type='Goal' and e.detail='Penalty')
   from af_fixtures f left join af_events e on e.fixture_id=f.fixture_id where f.season>=2021 group by 1 order by 1""")
for r in k.fetchall():
    print(r)
k.execute("""select to_char(market_time,'YYYY-MM') mo, count(distinct market_id) from bf_hist_other
   where sport='Soccer' and market_type='FIRST_HALF_GOALS_25' and market_time>='2023-07-01' and market_time<'2024-11-01' group by 1 order by 1""")
print(k.fetchall())
k.execute("""select to_char(market_time,'YYYY-MM') mo, count(distinct market_id) from bf_hist_other
   where sport='Soccer' and market_type='OVER_UNDER_25' and market_time>='2023-07-01' and market_time<'2024-11-01' group by 1 order by 1""")
print(k.fetchall())
