import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local()); cur = c.cursor()
cur.execute("select pid, usename, state, wait_event, now()-query_start, left(regexp_replace(coalesce(query,''),'\\s+',' ','g'),120) from pg_stat_activity where pid<>pg_backend_pid() and backend_type='client backend'")
for r in cur.fetchall(): print(*r)
