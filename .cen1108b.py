import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local()); cur = c.cursor()
cur.execute("SET work_mem='64MB'; SET statement_timeout='900s';")
key = ('', '')
pairs = []
while True:
    cur.execute("""select sport, market_type from bf_hist_other
                   where (sport, market_type) > (%s, %s)
                   order by sport, market_type limit 1""", key)
    r = cur.fetchone()
    if not r:
        break
    pairs.append(r); key = r
cur.execute("""select sport, market_type, count(distinct market_id), sum((status='WINNER')::int)
               from bf_hist_result group by 1,2""")
res = {(a, b): (n, w) for a, b, n, w in cur.fetchall()}
for s, mt in pairs:
    if s == 'Soccer':
        continue
    cur.execute("select min(market_time)::date from bf_hist_other where sport=%s and market_type=%s", (s, mt))
    a = cur.fetchone()[0]
    cur.execute("select max(market_time)::date from bf_hist_other where sport=%s and market_type=%s", (s, mt))
    b = cur.fetchone()[0]
    print(s, '|', mt, '|', a, b, '| result mkts, winners', res.get((s, mt)), flush=True)
print('soccer types', len([p for p in pairs if p[0] == 'Soccer']))
