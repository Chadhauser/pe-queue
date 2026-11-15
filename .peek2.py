import sys, psycopg2, glob, re, collections
sys.path.insert(0, '/root/pe-queue/runner'); import creds
con = psycopg2.connect(creds.pg_local()); cur = con.cursor()
cur.execute("SET statement_timeout='300s'")
cur.execute("SELECT market_type,count(*),count(DISTINCT market_id),count(DISTINCT substr(market_time::text,1,7)) FROM bf_hist_other WHERE sport='Soccer' GROUP BY 1 ORDER BY 3 DESC")
J = {f: open(f, errors='ignore').read() for f in glob.glob('/root/pe-queue/jobs/*.sh')}
Q = open('/root/pe-queue/watchman/FINDER_QUEUE.md').read()
for mt, rows, mk, months in cur.fetchall():
    print(mt, rows, mk, months, 'jobs', sum(mt in t for t in J.values()), 'queue', Q.count(mt))
cur.execute("SELECT event_name,count(DISTINCT market_id) FROM bf_hist_other WHERE sport='Cricket' GROUP BY 1")
E = cur.fetchall()
print('cricket events', len(E))
c = collections.Counter()
for e, n in E:
    k = 'W' if re.search(r'\bW(omen)?\b', e) else 'U19' if re.search(r'U19|U-19', e) else 'A' if re.search(r'\bA\b', e) else 'other'
    c[k] += n
print(c)
import random; random.seed(1)
print(random.sample([e for e, n in E], 25))
print([e for e, n in E if re.search(r'\bW(omen)?\b', e)][:15])
cur.execute("SELECT event_name,count(*) FROM racing_bsp WHERE market='win' GROUP BY 1 ORDER BY 2 DESC LIMIT 25")
print(cur.fetchall())
