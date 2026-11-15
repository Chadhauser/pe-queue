import sys, psycopg2, glob, re
sys.path.insert(0, '/root/pe-queue/runner')
import creds
con = psycopg2.connect(creds.pg_local())
c = con.cursor()
c.execute("SET statement_timeout='300s'; SET work_mem='64MB'")
jobs = [open(f, errors='ignore').read() for f in glob.glob('/root/pe-queue/jobs/*.sh')]
q = open('/root/pe-queue/watchman/FINDER_QUEUE.md').read()
h = open('/root/pe-queue/watchman/HYPOTHESES.md').read()
for lo, hi in (('2023-10-07', '2023-10-09'), ('2026-09-12', '2026-09-14')):
    c.execute("""SELECT sport, market_type, count(*), count(distinct market_id), sum(inplay::int)
                 FROM bf_hist_other WHERE market_time>=%s AND market_time<%s GROUP BY 1,2 ORDER BY 1, 4 DESC""", (lo, hi))
    print('==', lo)
    for s, t, n, m, ip in c.fetchall():
        nj = sum(1 for j in jobs if t in j)
        print(f"{s[:8]:8} {str(t)[:30]:30} rows {n:>8} mkts {m:>6} ip {ip:>7} jobs {nj:>3} q {q.count(str(t)):>3} h {h.count(str(t)):>3}")
c.execute("SELECT min(f.kickoff), max(f.kickoff), count(*), date_trunc('month',f.kickoff)::date, count(*) FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' GROUP BY 4 ORDER BY 4")
for r in c.fetchall():
    print(r[3], r[4])
