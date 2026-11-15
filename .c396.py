import sys,psycopg2,subprocess
sys.path.insert(0,'/root/pe-queue/runner'); import creds
c=psycopg2.connect(creds.pg_railway(),sslmode='require'); c.autocommit=True; k=c.cursor(); k.execute("SET statement_timeout='120s'")
for tb in ('ip_reopen','racing_form_features','cricket_fav_paper'):
    k.execute("SELECT column_name,data_type FROM information_schema.columns WHERE table_name=%s ORDER BY ordinal_position",(tb,)); print(tb,[f"{a}:{b[:6]}" for a,b in k.fetchall()])
    k.execute("SELECT reltuples::bigint,pg_total_relation_size(%s::regclass)/1048576 FROM pg_class WHERE relname=%s",(tb,tb)); print(' est rows, MB',k.fetchone())
    k.execute(f"SELECT * FROM {tb} LIMIT 2"); cols=[d[0] for d in k.description]
    for r in k.fetchall(): print('  ',{a:str(b)[:40] for a,b in zip(cols,r)})
k.execute("SELECT min(ts),max(ts),count(*) FROM ip_reopen") if False else None
k.execute("SELECT rule,count(*),count(result),avg(pnl_per_10) FROM cricket_fav_paper GROUP BY 1"); print('paper',k.fetchall())
# cricket tape in-play cadence
k.execute("""SELECT percentile_cont(array[.25,.5,.75]) WITHIN GROUP (ORDER BY g) FROM (SELECT extract(epoch from ts-lag(ts) OVER (PARTITION BY market_id,sel_name ORDER BY ts)) g FROM cricket_fav_tape WHERE inplay) x"""); print('in-play gap s p25 p50 p75',k.fetchone())
k.execute("""SELECT count(*),count(DISTINCT market_id) FROM cricket_fav_tape WHERE inplay"""); print(k.fetchone())
