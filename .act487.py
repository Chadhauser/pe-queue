import sys
sys.path.insert(0, '/root/pe-queue/runner'); import creds, psycopg2
con = psycopg2.connect(creds.pg_local()); cur = con.cursor()
cur.execute("""select pid, now()-query_start, state, wait_event_type, wait_event, left(query, 120) from pg_stat_activity
               where state <> 'idle' and pid <> pg_backend_pid() order by 2 desc""")
for r in cur.fetchall(): print(r)
