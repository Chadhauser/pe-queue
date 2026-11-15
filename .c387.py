import sys, collections
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local()); c.autocommit = True; k = c.cursor()
k.execute("SET work_mem='64MB'; SET statement_timeout='500s'")
k.execute("select sel,count(*) from liq_sample where mkt='CS' and ts>'2026-11-06' group by 1 order by 2 desc limit 22")
print(k.fetchall())
# last row per market and runner, lowest back of the last snapshot: no price of any OU25 runner is read here
k.execute("""
create temp table cs as select distinct on (market_id,sel) market_id,event_name,sel,back_px::float8 b,minute,ts
 from liq_sample where mkt='CS' and back_px is not null order by market_id,sel,ts desc""")
k.execute("""select count(*),count(*) filter (where lo<=1.05),count(*) filter (where lo>1.05 and lo<=1.2),count(*) filter (where lo>1.2 and lo<=1.5),count(*) filter (where lo>1.5)
 from (select market_id,min(b) lo from cs group by 1) z""")
print('CS markets: n, lowest last back <=1.05, <=1.2, <=1.5, >1.5', k.fetchone())
k.execute("""select count(distinct o.event_name),count(distinct c.event_name) from
 (select distinct event_name from liq_sample where mkt='OU25') o left join (select distinct event_name from cs) c using (event_name)""")
print('OU25 events, with CS', k.fetchone())
k.execute("""select distinct on (market_id) market_id,event_name,sel,b,minute,ts from cs order by market_id,b limit 8""")
for r in k.fetchall(): print(r)
c.close()
