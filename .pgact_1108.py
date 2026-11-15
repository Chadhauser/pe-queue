import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local()); cur = c.cursor()
cur.execute("""select pid, state, wait_event_type, wait_event, now()-query_start, left(regexp_replace(query,'\\s+',' ','g'),150)
               from pg_stat_activity where state<>'idle' and pid<>pg_backend_pid() order by query_start""")
for r in cur.fetchall(): print(r)
