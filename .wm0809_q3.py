import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
l = psycopg2.connect(creds.pg_local())
l.autocommit = True
c = l.cursor()
def q(sql, a=None, n=40):
    try:
        c.execute(sql, a)
        rows = c.fetchall()
        for row in rows[:n]: print(row)
        return rows
    except Exception as e:
        print('ERR', str(e).splitlines()[0])
c.execute("select inet_server_addr(), current_database()"); print('local db', c.fetchone())
print('== suite')
q("select run_at, status, count(*) from integrity_suite where run_at=(select max(run_at) from integrity_suite) group by 1,2")
q("select chk, value, left(detail,140) from integrity_suite where run_at=(select max(run_at) from integrity_suite) and status<>'PASS' order by chk")
q("select run_at, count(*) filter (where status='PASS'), count(*) filter (where status<>'PASS') from integrity_suite where run_at > now()-interval '30 hours' group by 1 order by 1")
for t in ('boring_results_v3','rgrid_survivors','gs_vs_market','coach_tape','grid_survivors_v3'):
    print('== cols', t)
    q("select string_agg(column_name||':'||data_type, ', ' order by ordinal_position) from information_schema.columns where table_name=%s and table_schema='public'", (t,))
    q(f"select count(*) from {t}")
print('== tape_archive_wm cols')
q("select string_agg(column_name, ', ' order by ordinal_position) from information_schema.columns where table_name='tape_archive_wm'")
q("select now()")
