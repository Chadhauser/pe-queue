import sys,psycopg2
sys.path.insert(0,'/root/pe-queue/runner'); import creds
con=psycopg2.connect(creds.pg_local()); cur=con.cursor()
cur.execute("SET work_mem='64MB'; SET statement_timeout='600s'")
cur.execute("""SELECT sport,market_type,count(DISTINCT market_id),count(*),sum((inplay)::int) FROM bf_hist_other
 WHERE market_time>='2026-09-12' AND market_time<'2026-09-14' GROUP BY 1,2 ORDER BY 1,3 DESC""")
for r in cur.fetchall(): print(r)
import subprocess,re,glob
used=set()
for f in glob.glob('jobs/*.sh')+glob.glob('jobs/*.py'):
    used|=set(re.findall(r"[A-Z][A-Z0-9_]{3,}",open(f,errors='ignore').read()))
cur.execute("""SELECT DISTINCT market_type FROM bf_hist_other WHERE market_time>='2026-09-12' AND market_time<'2026-09-14'""")
print('never named in jobs:',[m for (m,) in cur.fetchall() if m not in used])
