import sys, time
sys.path.insert(0, '/root/pe-queue/runner'); import creds, psycopg2
L = psycopg2.connect(creds.pg_local()); L.autocommit = True; c = L.cursor()
c.execute("SET work_mem='64MB'; SET statement_timeout='600s'")
for q in ["select exchange,count(*),min(ts),max(ts),count(distinct event_name) from xx_pre_329 group by 1",
          "select exchange,count(*),min(ts),max(ts),count(distinct event_name) from xx_ip_331 group by 1",
          "select max(ts),min(ts) from liq_sample",
          "select column_name from information_schema.columns where table_name='xx_ip_331'",
          "select column_name from information_schema.columns where table_name='liq_sample'"]:
    t = time.time()
    try:
        c.execute(q); print(q[:60], c.fetchall(), round(time.time() - t, 1), 's', flush=True)
    except Exception as e:
        print(q[:60], 'ERR', e, flush=True)
R = psycopg2.connect(creds.pg_railway()); R.autocommit = True; r = R.cursor(); r.execute("SET statement_timeout='300s'")
r.execute("select count(*) filter (where state='active' and now()-query_start>interval '5 minutes'), count(*) filter (where state='active') from pg_stat_activity"); print('railway busy', r.fetchone(), flush=True)
t = time.time()
r.execute("select column_name from information_schema.columns where table_name='xx_tape'"); print([x[0] for x in r.fetchall()])
r.execute("select exchange, min(ts), max(ts) from xx_tape where ts > now() - interval '2 hours' group by 1"); print('xx_tape recent', r.fetchall(), round(time.time() - t, 1), 's')
t = time.time()
r.execute("select min(ts) from xx_tape"); print('xx_tape min', r.fetchall(), round(time.time() - t, 1), 's')
