import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local()); cur = c.cursor()
cur.execute("select pid, state, now()-query_start, left(regexp_replace(query,'\\s+',' ','g'),110) from pg_stat_activity where state<>'idle' and pid<>pg_backend_pid() order by 3 desc")
for r in cur.fetchall(): print(*r)
cur.execute("select now()")
print(cur.fetchone()[0])
