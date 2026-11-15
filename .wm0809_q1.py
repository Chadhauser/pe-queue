import sys, re
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
r = psycopg2.connect(creds.pg_railway())
c = r.cursor()
c.execute("select inet_server_addr() is not null, current_database()")
print('railway db check', c.fetchone())
handled = set(l.strip() for l in open('/root/pe-watchman/handled.txt') if l.strip())
c.execute("""select job, status, exit_code, finished, log from job_results
 where finished > now() - interval '3 hours' order by finished""")
print('== failures last 3h')
for job, st, ec, fin, log in c.fetchall():
    log = log or ''
    bad = st == 'failed' or 'Traceback' in log or re.search(r'(?m)^Error', log)
    if bad:
        print(job, st, ec, fin, 'HANDLED' if job in handled else 'NEW')
print('== integrity_log ok=false 2h')
c.execute("select chk, count(*), max(ts) from integrity_log where ok=false and ts > now()-interval '2 hours' group by chk order by 2 desc")
for row in c.fetchall(): print(row)
for t in ('stream_ticks', 'liq_sample'):
    c.execute("select column_name from information_schema.columns where table_name=%s and data_type like 'timestamp%%'", (t,))
    cols = [x[0] for x in c.fetchall()]
    for col in cols[:2]:
        c.execute(f"select max({col}), count(*) filter (where {col} > now()-interval '15 minutes') from {t} where {col} > now()-interval '1 hour'")
        print(t, col, c.fetchone())
print('== heartbeats')
c.execute("select table_name from information_schema.tables where table_name like '%%_heartbeat' and table_schema='public'")
for (t,) in c.fetchall():
    c.execute("select column_name from information_schema.columns where table_name=%s and data_type like 'timestamp%%'", (t,))
    cols = [x[0] for x in c.fetchall()]
    if cols:
        c.execute(f"select max({cols[0]}), now()-max({cols[0]}) from {t}")
        print(t, c.fetchone())
print('== bot_status stopped')
try:
    c.execute("select * from bot_status")
    for row in c.fetchall():
        if 'STOP' in str(row).upper(): print(row)
except Exception as e:
    print('bot_status err', e); r.rollback()
print('== delete_trap')
try:
    c.execute("select column_name from information_schema.columns where table_name='delete_trap' order by ordinal_position")
    print([x[0] for x in c.fetchall()])
    c.execute("select count(*) from delete_trap")
    print('rows', c.fetchone())
    c.execute("select * from delete_trap order by 1 desc limit 6")
    for row in c.fetchall(): print(row)
except Exception as e:
    print('delete_trap err', e); r.rollback()
print('== scoreboard')
c.execute("select finished, log from job_results where job='SPORTS_SCOREBOARD' order by finished desc limit 1")
f, log = c.fetchone()
print(f)
print(log[:5000])
