import sys, time
sys.path.insert(0, '/root/pe-queue/runner'); import creds, psycopg2
con = psycopg2.connect(creds.pg_local()); con.autocommit = True; cur = con.cursor()
# only this job's own unseen-pull query (its text names market_type as a selected column in the DISTINCT ON list)
cur.execute("""select pid from pg_stat_activity where state='active' and pid<>pg_backend_pid() and backend_type='client backend'
               and query like '%DISTINCT ON (market_id, sel) market_id, market_type, sel, market_time, ts, ltp AS close_ltp%'""")
pids = [r[0] for r in cur.fetchall()]; print('cancel', pids)
for p in pids:
    cur.execute("select pg_cancel_backend(%s)", (p,)); print(p, cur.fetchone())
time.sleep(3)
cur.execute("select count(*) from pg_stat_activity where state='active' and pid<>pg_backend_pid() and query like '%market_type, sel, market_time, ts, ltp AS close_ltp%'")
print('still active', cur.fetchone())
