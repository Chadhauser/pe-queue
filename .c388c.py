import sys, glob, re
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
txt = {}
for p in glob.glob('/root/pe-queue/jobs/*'):
    if p.endswith(('.sh', '.wip', '.py')):
        txt[p] = open(p, errors='replace').read()
for name, dsn in (('LOCAL', creds.pg_local()), ('RAILWAY', creds.pg_railway())):
    try:
        c = psycopg2.connect(dsn, connect_timeout=20); cur = c.cursor()
        cur.execute("SET statement_timeout='60s'")
        cur.execute("""select c.relname,c.reltuples::bigint from pg_class c join pg_namespace n on n.oid=c.relnamespace
                       where n.nspname='public' and c.relkind in ('r','p') and c.reltuples>500 order by 2 desc""")
        print('==', name)
        for t, n in cur.fetchall():
            if re.match(r'(finder_|tmp_|t_|f_\d|_)', t): continue
            hits = [p for p, s in txt.items() if t in s]
            f = sum(1 for p in hits if '/499_' in p or '/45' in p or '/46' in p or '/47' in p or '/48' in p or '/49' in p)
            print(f'  {t:38s} {n:>12,} jobs {len(hits):>3} finder {f:>3}')
    except Exception as e:
        print(name, 'FAILED', type(e).__name__)
for l in open('/root/pe-queue/watchman/FINDER_QUEUE.md'):
    if re.match(r'^(38[2-9])\. ', l):
        print(l[:1100].rstrip()); print()
