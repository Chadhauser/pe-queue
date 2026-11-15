import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local()); c.autocommit = True; k = c.cursor()
k.execute("SET work_mem='64MB'; SET statement_timeout='500s'")
k.execute("select max(captured_at),count(*) from goal_timeline"); print('local goal_timeline', k.fetchone())
k.execute("select status,count(*) from goal_timeline where captured_at>'2026-10-20' group by 1 order by 2 desc limit 12"); print(k.fetchall())
k.execute("select home_team,away_team,minute,score_home,score_away,status,captured_at from goal_timeline order by captured_at desc limit 3"); print(k.fetchall())
k.execute("select event_name,market_id,mkt,ts from liq_sample where mkt='OU25' order by ts desc limit 3"); print(k.fetchall())
# signal-tick book on one small slice: football MO, Q 1.1, first 2 days' markets
k.execute("""
create temp table s as select market_id,sel_id,pt,back_px::float8 b,lay_px::float8 l,back_sz::float8 bs,ltp::float8 ltp from stream_ticks
 where sport='football' and mkt='MO' and inplay and status='OPEN' and pt<'2026-11-03'
""")
k.execute("""
with h as (select distinct on (market_id,sel_id) market_id,sel_id,pt,b,l,bs,ltp from s where b<=1.1 order by market_id,sel_id,pt)
select count(*),percentile_cont(array[.1,.5,.9]) within group (order by coalesce(l,1000)),percentile_cont(array[.1,.5,.9]) within group (order by bs),
   count(*) filter (where l is null), count(*) filter (where l<=1.155), count(*) filter (where ltp<=1.155) from h""")
print('football MO signal at Q 1.1: n, lay pctl, back size pctl, no lay, lay<=1.155, ltp<=1.155', k.fetchall())
c.close()
r = psycopg2.connect(creds.pg_railway(), sslmode='require'); q = r.cursor(); q.execute("SET statement_timeout='200s'")
q.execute("select max(captured_at),count(*) from goal_timeline"); print('railway goal_timeline', q.fetchone())
q.execute("select status,count(*) from goal_timeline where captured_at>now()-interval '6 days' group by 1 order by 2 desc limit 12"); print(q.fetchall())
q.execute("select count(*),max(event_id) from event_results"); print(q.fetchone())
r.close()
