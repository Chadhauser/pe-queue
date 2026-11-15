import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local()); cur = c.cursor()
cur.execute("SET statement_timeout='300s'")
cur.execute("select column_name from information_schema.columns where table_name='bf_hist_other' order by ordinal_position")
print([r[0] for r in cur.fetchall()])
src = open('/root/pe-queue/jobs/499_ht_state_thin.sh').read()
import re
for k in ('friendl', 'Friendl', 'competition', 'comp', 'women', 'youth', 'U21', 'U19'):
    print(k, src.count(k))
