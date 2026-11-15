import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
l = psycopg2.connect(creds.pg_local())
l.autocommit = True
c = l.cursor()
def q(sql, a=None, n=30):
    try:
        c.execute(sql, a)
        rows = c.fetchall()
        for row in rows[:n]: print(row)
        return rows
    except Exception as e:
        print('ERR', str(e).splitlines()[0])
print('== integrity_suite latest')
q("select column_name from information_schema.columns where table_name='integrity_suite' order by ordinal_position")
q("select max(run_ts) from integrity_suite")
print('== tables present')
q("select table_name from information_schema.tables where table_schema='public' and table_name in ('boring_results_v3','rgrid_survivors','gs_vs_market','coach_tape','grid_survivors_v3','tape_archive_wm','bookie_paper') order by 1")
print('== tape_archive_wm')
q("select * from tape_archive_wm")
