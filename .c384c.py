import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local()); c.autocommit = True; k = c.cursor()
k.execute("SET work_mem='64MB'; SET statement_timeout='500s'")
k.execute("""
create temp table tmp_e as
select distinct on (market_id,sel_id) market_id,sport,mkt,sel_id,sel,back_px::float8 b,lay_px::float8 l,pt
from stream_ticks where sport in ('football','tennis') and mkt='MO' and inplay and status='OPEN' and back_px is not null
order by market_id,sel_id,pt desc
""")
k.execute("""select sport,count(*),
  count(*) filter (where lo<=1.03), count(*) filter (where lo>1.03 and lo<=1.1), count(*) filter (where lo>1.1 and lo<=1.3), count(*) filter (where lo>1.3)
  from (select market_id,sport,min(b) lo from tmp_e group by 1,2) z group by 1""")
print('lowest last OPEN back per market: sport,n,<=1.03,<=1.1,<=1.3,>1.3')
for r in k.fetchall(): print(r)
k.execute("""select sport,percentile_cont(array[0.1,0.5,0.9]) within group (order by mins) from (
   select s.market_id,s.sport,extract(epoch from max(s.pt)-min(s.pt))/60 mins from stream_ticks s
   where s.sport in ('football','tennis') and s.mkt='MO' and s.inplay group by 1,2) z group by 1""")
print('in-play span minutes p10,p50,p90', k.fetchall())
k.execute("""select count(distinct s.market_id),count(distinct l.market_id) from (select distinct market_id from stream_ticks where sport='football' and mkt='MO' and inplay) s
   left join (select distinct market_id from liq_sample where mkt='MO') l using (market_id)""")
print('stream football MO markets, also on liq_sample', k.fetchall())
c.close()
r = psycopg2.connect(creds.pg_railway(), sslmode='require'); q = r.cursor(); q.execute("SET statement_timeout='120s'")
q.execute("select table_name from information_schema.tables where table_schema='public' and (table_name ilike '%result%' or table_name ilike '%settle%' or table_name ilike '%tennis%') order by 1")
L = [x[0] for x in q.fetchall()]; print('railway', L)
for t in ('event_results', 'market_results', 'tennis_market_results', 'football_market_results', 'racing_results'):
    if t in L:
        q.execute("select column_name from information_schema.columns where table_name=%s order by ordinal_position", (t,))
        cols = [x[0] for x in q.fetchall()]; print(t, cols)
        q.execute(f"select count(*) from {t}"); print(' rows', q.fetchone())
r.close()
