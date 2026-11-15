import sys, glob
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_railway(), connect_timeout=20); c.autocommit = True
cur = c.cursor()
cur.execute("SET statement_timeout='120s'")
for t in ('bf_racing_log', 'bf_tennis_log', 'bf_price_log'):
    print('==', t)
    cur.execute("select indexdef from pg_indexes where tablename=%s", (t,))
    for r in cur.fetchall(): print('  idx', r[0][:110])
    cur.execute(f"select * from {t} order by id desc limit 3")
    print('  cols', [d[0] for d in cur.description])
    for r in cur.fetchall(): print('  ', str(tuple(r))[:400])
    cur.execute(f"select min(id),max(id) from {t}")
    lo, hi = cur.fetchone(); print('  ids', lo, hi)
    cur.execute(f"select * from {t} order by id limit 1")
    print('  first', str(cur.fetchone())[:300])
    # per-day row count from a 1% systematic sample of ids, cheap on the pk
    ts = 'captured_at' if t != 'bf_price_log' else None
    if ts:
        cur.execute(f"""select {ts}::date, count(*), count(distinct market_id), round(min(mins_to_off)), round(max(mins_to_off))
                        from {t} where id > %s group by 1 order by 1 desc limit 8""", (hi - 400000,))
        for r in cur.fetchall(): print('  day', r)
        cur.execute(f"select min({ts}), max({ts}) from {t} where id in (%s,%s)", (lo, hi))
        print('  range', cur.fetchone())
for p in glob.glob('/root/pe-queue/jobs/*'):
    if p.endswith('.sh'):
        s = open(p, errors='replace').read()
        for t in ('bf_racing_log', 'bf_tennis_log', 'bf_golf_log'):
            if t in s: print(t, p)
