import sys, re
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
R = psycopg2.connect(creds.pg_railway(), connect_timeout=20)
L = psycopg2.connect(creds.pg_local(), connect_timeout=20)
for n, c in (('railway', R), ('local', L)):
    cur = c.cursor(); cur.execute("select inet_server_addr(), current_database(), now()"); print(n, 'host', cur.fetchone())
def q(conn, sql, a=None):
    cur = conn.cursor()
    try:
        cur.execute("set statement_timeout=60000"); cur.execute(sql, a); return cur.fetchall()
    except Exception as e:
        conn.rollback(); return [('ERR', repr(e)[:200])]
print('== failed/err jobs last 3h (railway job_results)')
for r in q(R, """select job, finished, status, exit_code, log from job_results where finished > now()-interval '3 hours'
  and (status='failed' or log ~ 'Traceback' or log ~ '(^|\\n)Error') order by finished"""):
    if r[0] == 'ERR': print(r); continue
    print('---', r[0], r[1], r[2], r[3]); print((r[4] or '')[-1500:])
print('== running / recent jobs last 3h')
for r in q(R, "select job, started, finished, status, exit_code from job_results where coalesce(finished,started) > now()-interval '3 hours' and job<>'SPORTS_SCOREBOARD' order by started"):
    print(r)
print('== integrity_log ok=false 2h')
for c, nm in ((R, 'railway'), (L, 'local')):
    print(nm, q(c, "select chk, count(*), max(ts) from integrity_log where ok=false and ts>now()-interval '2 hours' group by chk order by 2 desc"))
print('== freshness')
for c, nm in ((R, 'railway'), (L, 'local')):
    print(nm, 'stream_ticks', q(c, "select max(ts_recv), count(*) filter (where ts_recv>now()-interval '15 minutes') from stream_ticks where ts_recv>now()-interval '1 day'"))
    print(nm, 'liq_sample', q(c, "select max(ts), count(*) filter (where ts>now()-interval '15 minutes') from liq_sample where ts>now()-interval '1 day'"))
print('== heartbeats')
for c, nm in ((R, 'railway'), (L, 'local')):
    for (t,) in q(c, "select table_name from information_schema.tables where table_name like '%%heartbeat%%' and table_schema='public'"):
        cols = [x[0] for x in q(c, "select column_name from information_schema.columns where table_name=%s and data_type like 'timestamp%%'", (t,))]
        if cols:
            print(nm, t, q(c, f'select max("{cols[0]}") from {t}'))
print('== bot_status STOPPED')
print(q(R, "select * from bot_status where status ilike '%%stop%%'"))
print('== delete_trap last 24h')
print(q(R, "select * from delete_trap where ts>now()-interval '24 hours' order by ts desc limit 10"))
print('== tape_archive_wm')
print(q(L, "select * from tape_archive_wm"))
print('== integrity_suite latest')
for r in q(L, "select * from integrity_suite where run_ts=(select max(run_ts) from integrity_suite) and not ok"):
    print(r)
print(q(L, "select max(run_ts), count(*) filter (where ok), count(*) filter (where not ok) from integrity_suite where run_ts=(select max(run_ts) from integrity_suite)"))
print('== scoreboard')
r = q(R, "select finished, log from job_results where job='SPORTS_SCOREBOARD' order by finished desc nulls last limit 1")
print(r[0][0]); print(r[0][1][:3500] if r and r[0][0] != 'ERR' else r)
print('== survivors')
for c, nm, sql in (
  (L, 'local boring_results_v3', "select * from boring_results_v3 limit 0"),
  (L, 'local grid_survivors_v3', "select count(*) from grid_survivors_v3"),
  (L, 'local rgrid_survivors', "select count(*) from rgrid_survivors"),
  (R, 'railway rgrid_survivors', "select count(*) from rgrid_survivors"),
  (L, 'local gs_vs_market', "select count(*) from gs_vs_market"),
  (R, 'railway gs_vs_market', "select count(*) from gs_vs_market"),
  (R, 'railway coach_tape 7d', "select count(*), max(ts) from coach_tape where ts>now()-interval '7 days'"),
  (L, 'local coach_tape 7d', "select count(*), max(ts) from coach_tape where ts>now()-interval '7 days'")):
    print(nm, q(c, sql))
print('== report jobs last 6h')
jobs = [l.strip() for l in open('/root/pe-queue/watchman/REPORT_JOBS.txt') if l.strip()]
for j in jobs:
    r = q(R, "select job, status, finished, log from job_results where finished>now()-interval '6 hours' and (job=%s or job like %s) order by finished desc limit 1", (j, j + '\\_%'))
    if r and r[0][0] != 'ERR':
        print('###', r[0][0], r[0][1], r[0][2])
