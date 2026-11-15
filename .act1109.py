import sys,psycopg2
sys.path.insert(0,'/root/pe-queue/runner'); import creds
con=psycopg2.connect(creds.pg_local()); cur=con.cursor()
cur.execute("SELECT pid, now()-query_start, state, left(regexp_replace(query,'\\s+',' ','g'),140) FROM pg_stat_activity WHERE state<>'idle' AND pid<>pg_backend_pid()")
for r in cur.fetchall(): print(r)
cur.execute("SELECT now()")
print(cur.fetchone())
