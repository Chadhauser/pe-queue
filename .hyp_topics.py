import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2, subprocess, glob, re

rows = open('watchman/HYPOTHESES.md').read().split('\n')
out = []
for r in rows:
    p = [x.strip() for x in r.split('|')]
    if len(p) >= 3:
        out.append(p[1][:18] + ' | ' + p[2][:88])
print('\n'.join(out))

c = psycopg2.connect(creds.pg_local())
k = c.cursor()
k.execute("""select relname, n_live_tup from pg_stat_user_tables order by n_live_tup desc""")
tabs = k.fetchall()
print('\n== LOCAL TABLES (name, est rows, jobs mentioning)')
blob = {}
for f in glob.glob('jobs/*.sh'):
    try:
        blob[f] = open(f, errors='ignore').read()
    except Exception:
        pass
for t, n in tabs:
    if n < 200:
        continue
    if re.search(r'_\d{3}$|^x_|^tmp|^t\d', t):
        continue
    m = sum(1 for b in blob.values() if t in b)
    print(t, n, m)
