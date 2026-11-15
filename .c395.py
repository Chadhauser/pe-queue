import sys,psycopg2
sys.path.insert(0,'/root/pe-queue/runner'); import creds
c=psycopg2.connect(creds.pg_railway(),sslmode='require'); c.autocommit=True; k=c.cursor(); k.execute("SET statement_timeout='120s'")
k.execute("SELECT column_name,data_type FROM information_schema.columns WHERE table_name='cricket_fav_tape' ORDER BY ordinal_position"); print(k.fetchall())
k.execute("SELECT reltuples::bigint,pg_total_relation_size('cricket_fav_tape')/1048576 FROM pg_class WHERE relname='cricket_fav_tape'"); print('rows est, MB',k.fetchone())
k.execute("SELECT * FROM cricket_fav_tape LIMIT 4")
cols=[d[0] for d in k.description]
for r in k.fetchall(): print(dict(zip(cols,r)))
tc=[x for x in cols if x in('ts','captured_at','ts_utc','recorded_at','created_at')]
print('time col',tc)
if tc:
    t=tc[0]
    k.execute(f"SELECT min({t}),max({t}),count(*) FROM cricket_fav_tape"); print(k.fetchone())
    k.execute(f"SELECT date_trunc('month',{t}) m,count(*) FROM cricket_fav_tape GROUP BY 1 ORDER BY 1"); print(k.fetchall())
k.execute("SELECT min(match_date),max(match_date),count(*) FROM cricket_matches"); print('cricket_matches',k.fetchone())
for tb in ('cricket_fav_tape',):
    k.execute("SELECT pid,state,now()-query_start,left(query,60) FROM pg_stat_activity WHERE state='active' AND now()-query_start>interval '60 s'"); print('slow active',k.fetchall())
