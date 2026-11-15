import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
L = psycopg2.connect(creds.pg_local(), connect_timeout=20)
def q(sql, a=None):
    cur = L.cursor()
    try:
        cur.execute("set statement_timeout=60000"); cur.execute(sql, a); return cur.fetchall()
    except Exception as e:
        L.rollback(); return [('ERR', repr(e)[:200])]
for t in ('integrity_suite', 'delete_trap', 'coach_tape', 'boring_results_v3'):
    print(t, [x[0] for x in q("select column_name from information_schema.columns where table_name=%s and table_schema='public' order by ordinal_position", (t,))])
