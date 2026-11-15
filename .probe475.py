import sys,time,psycopg2,pandas as pd
sys.path.insert(0,'/root/pe-queue/runner'); import creds
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='900s'")
cur.execute("select indexname,indexdef from pg_indexes where tablename='bf_hist_other'"); [print(r) for r in cur.fetchall()]
cur.execute("select column_name,data_type from information_schema.columns where table_name='bf_hist_other' order by ordinal_position"); print(cur.fetchall())
cur.execute("select pg_size_pretty(pg_total_relation_size('bf_hist_other'))"); print(cur.fetchone())
t=time.time()
cur.execute("""select count(*), count(distinct event_id) from bf_hist_other where sport='Soccer' and market_type='OVER_UNDER_05' and inplay
  and market_time>='2023-03-01' and market_time<'2023-03-08'""" ); print(cur.fetchone(), time.time()-t)
cur.execute("select count(*) from af_price_map m where exists (select 1 from bf_hist_other o where o.event_id=m.event_id and o.market_time>='2025-03-01' and o.market_time<'2025-03-08' and o.market_type='MATCH_ODDS' limit 1)"); print('mapped events seen in other, 1 wk Mar 2025:',cur.fetchone())
cur.execute("select sport_month, status from bf_hist_months where sport='Soccer' order by 1" if False else "select column_name from information_schema.columns where table_name='bf_hist_months'"); print(cur.fetchall())
