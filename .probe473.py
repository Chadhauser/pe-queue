import sys,psycopg2,pandas as pd
sys.path.insert(0,'/root/pe-queue/runner'); import creds
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='600s'")
cur.execute("select column_name,data_type from information_schema.columns where table_name='bf_hist_price' order by ordinal_position"); print(cur.fetchall())
cur.execute("select column_name from information_schema.columns where table_name='af_price_map' order by ordinal_position"); print(cur.fetchall())
cur.execute("select column_name from information_schema.columns where table_name='af_events' order by ordinal_position"); print(cur.fetchall())
cur.execute("select count(*), count(distinct event_id) from af_price_map"); print(cur.fetchall())
cur.execute("select event_id from af_price_map limit 1 offset 500"); e=cur.fetchone()[0]; print('eid',e)
P=pd.read_sql("select minute,mkt,sel,ltp from bf_hist_price where event_id=%s and mkt in ('MO','OU25') order by mkt,sel,minute",con,params=(e,))
print(P.groupby(['mkt','sel']).minute.agg(['min','max','count']))
s=P[(P.mkt=='MO')&(P.sel=='DRAW')]
print(s.head(100).to_string())
