import sys, glob, os, time
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
L = psycopg2.connect(creds.pg_local(), connect_timeout=20)
def q(sql, a=None):
    cur = L.cursor()
    try:
        cur.execute("set statement_timeout=90000"); cur.execute(sql, a); return cur.fetchall()
    except Exception as e:
        L.rollback(); return [('ERR', repr(e)[:200])]
print('suite', q("select max(run_at), count(*) filter (where status='PASS'), count(*) filter (where status<>'PASS') from integrity_suite where run_at=(select max(run_at) from integrity_suite)"))
for r in q("select chk, status, value, left(detail,120) from integrity_suite where run_at=(select max(run_at) from integrity_suite) and status<>'PASS'"):
    print('  ', r)
print('delete_trap 24h', q("select tbl, app, usr, count(*), min(seen), max(seen) from delete_trap where seen>now()-interval '24 hours' group by 1,2,3 order by 5"))
print('delete_trap since 09 UTC', q("select tbl, app, count(*), max(seen), left(max(query),100) from delete_trap where seen>now()-interval '4 hours' group by 1,2"))
print('boring_v3', q("select count(*), count(*) filter (where t>=3.5 and h1>0 and h2>0 and per10>=0.15) from boring_results_v3"))
print('coach 7d', q("""select line, count(*), round(avg(pnl10)::numeric,2),
  round((avg(pnl10)/nullif(stddev(pnl10),0)*sqrt(count(*)))::numeric,2) from coach_tape
  where tape_date>=current_date-7 group by line order by 3 desc"""))
print('coach 7d halves', q("""with x as (select line, pnl10, ntile(2) over (partition by line order by tape_date, match) h from coach_tape where tape_date>=current_date-7)
  select line, round(avg(pnl10) filter (where h=1)::numeric,2), round(avg(pnl10) filter (where h=2)::numeric,2) from x group by line"""))
print('grid_v3', q("select count(*) from grid_survivors_v3"))
fs = sorted(glob.glob('/root/pe-queue/reports/finder_*.md'), key=os.path.getmtime)
if fs:
    f = fs[-1]; print('finder newest', f, round((time.time() - os.path.getmtime(f)) / 3600, 1), 'h old')
