import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local()); c.autocommit = True; k = c.cursor()
k.execute("SET work_mem='64MB'; SET statement_timeout='500s'")
k.execute("select status,sport,count(*),count(distinct market_id) from stream_ticks where sport in ('football','tennis') group by 1,2 order by 3 desc")
for r in k.fetchall(): print(r)
# how each in-play market ends: last tick per runner, min of last ltp per market
k.execute("""
create temp table tmp_e as
select distinct on (market_id,sel_id) market_id,sport,mkt,sel_id,sel,ltp::float8 ltp,back_px::float8 b,lay_px::float8 l,status,pt
from stream_ticks where sport in ('football','tennis') and mkt in ('MO','OU25') and inplay
order by market_id,sel_id,pt desc
""")
k.execute("""
select sport,mkt,count(*) mk,
  count(*) filter (where lo<=1.02) lo102, count(*) filter (where lo>1.02 and lo<=1.1) lo11,
  count(*) filter (where lo>1.1) lo_hi,
  count(*) filter (where n1>1) two_low, min(last_t), max(last_t)
from (select market_id,sport,mkt,min(coalesce(ltp,99)) lo,count(*) filter (where ltp<=1.02) n1,max(pt) last_t from tmp_e group by 1,2,3) z group by 1,2 order by 1,2
""")
for r in k.fetchall(): print(r)
k.execute("select sport,mkt,market_id,sel,ltp,b,l,status from tmp_e order by random() limit 12")
for r in k.fetchall(): print(r)
# which results sit locally, and are the stream's market ids in them
k.execute("select table_name from information_schema.tables where table_schema='public' and (table_name ilike '%result%' or table_name ilike '%tennis%') order by 1")
print([x[0] for x in k.fetchall()])
k.execute("select mkt,count(*),count(distinct market_id),min(ts),max(ts) from liq_sample group by 1 order by 2 desc limit 8")
for r in k.fetchall(): print(r)
c.close()
r = psycopg2.connect(creds.pg_railway(), sslmode='require'); q = r.cursor(); q.execute("SET statement_timeout='120s'")
q.execute("select table_name from information_schema.tables where table_schema='public' and (table_name ilike '%result%' or table_name ilike '%settle%' or table_name ilike '%tennis%') order by 1")
print('railway', [x[0] for x in q.fetchall()])
r.close()
