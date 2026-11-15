import sys, glob, re, psycopg2
sys.path.insert(0, '/root/pe-queue/runner')
import creds
text = {}
for f in glob.glob('/root/pe-queue/jobs/*'):
    if f.endswith('.pyc') or '__pycache__' in f:
        continue
    try:
        text[f.split('/')[-1]] = open(f, errors='ignore').read()
    except Exception:
        pass
print('jobs', len(text))
for name, dsn in (('LOCAL', creds.pg_local()), ('RAILWAY', creds.pg_railway())):
    c = psycopg2.connect(dsn, connect_timeout=20)
    cur = c.cursor()
    cur.execute("SET statement_timeout='60s'")
    cur.execute("""select relname, reltuples::bigint, pg_total_relation_size(oid)/1048576
                   from pg_class where relkind in ('r','p') and relnamespace='public'::regnamespace
                   and reltuples > 500 order by 1""")
    print('==', name)
    for t, n, mb in cur.fetchall():
        if t.startswith(('finder_', 'tmp_', 'f_')):
            continue
        hits = [j for j, s in text.items() if re.search(r'\b%s\b' % re.escape(t), s) and j.startswith('499')]
        if len(hits) <= 2:
            print(f'{t:34s} {n:>12,} {mb:>7}MB  499-jobs={len(hits)} {hits[:2]}')
    c.close()
c = psycopg2.connect(creds.pg_local())
cur = c.cursor()
cur.execute("""select market_type, count(distinct market_id), count(*) from bf_hist_other
               where sport='Soccer' and market_time >= '2024-08-01' and market_time < '2024-10-31'
               group by 1 order by 2 desc""")
print('== soccer market types Aug-Oct 2024')
for mt, m, n in cur.fetchall():
    hits = [j for j, s in text.items() if mt in s and j.startswith('499')]
    print(f'{mt:34s} markets {m:>7,} rows {n:>10,} 499-jobs={len(hits)}')
