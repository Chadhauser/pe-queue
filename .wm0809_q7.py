import sys, time
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
r = psycopg2.connect(creds.pg_railway(), connect_timeout=20); r.autocommit = True
c = r.cursor()
sql = "select relname, n_tup_ins from pg_stat_user_tables where relname in ('liq_sample','stream_ticks','ip_tape') order by 1"
c.execute(sql); a = dict(c.fetchall()); time.sleep(60); c.execute(sql); b = dict(c.fetchall())
print('inserts in 60 s:', {k: b[k] - a[k] for k in a})
