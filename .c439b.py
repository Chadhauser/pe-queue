import sys, re
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
txt = open('watchman/HYPOTHESES.md').read() + open('watchman/FINDER_QUEUE.md').read()
c = psycopg2.connect(creds.pg_local())
cur = c.cursor()
cur.execute("SET statement_timeout='600s';")
cur.execute("""select relname, n_live_tup from pg_stat_user_tables order by n_live_tup desc""")
for name, n in cur.fetchall():
    if n < 1000 or name.startswith('finder_') or re.match(r'.*_\d{3}$', name):
        continue
    k = len(re.findall(r'\b' + re.escape(name) + r'\b', txt))
    if k <= 2:
        cur.execute("select column_name from information_schema.columns where table_name=%s order by ordinal_position", (name,))
        cols = [r[0] for r in cur.fetchall()]
        print(name, n, 'mentions', k, cols[:18])
