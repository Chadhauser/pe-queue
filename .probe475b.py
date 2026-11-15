import sys,time,psycopg2,pandas as pd
sys.path.insert(0,'/root/pe-queue/runner'); import creds
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='900s'")
cur.execute("select y,m,status from bf_hist_months where sport='Soccer' order by y,m"); print(' '.join(f"{y}-{m:02d}:{s[:4]}" for y,m,s in cur.fetchall()))
for lo,hi in (('2024-09-07','2024-09-09'),('2025-09-13','2025-09-15')):
    cur.execute("select count(distinct o.event_id), count(distinct o.event_id) filter (where m.event_id is not null) from (select distinct event_id from bf_hist_other where sport='Soccer' and market_type='MATCH_ODDS' and market_time>=%s and market_time<%s) o left join af_price_map m on m.event_id=o.event_id",(lo,hi)); print(lo,cur.fetchone())
cur.execute("select min(m), max(m) from bf_hist_price"); print('bf_hist_price span',cur.fetchone())
