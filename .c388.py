import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local()); cur = c.cursor()
cur.execute("SET work_mem='64MB'; SET statement_timeout='600s'")
for t in ('bf_hist_other', 'bf_hist_result', 'bf_hist_months', 'bf_hist_markets'):
    cur.execute("select column_name,data_type from information_schema.columns where table_name=%s order by ordinal_position", (t,))
    print(t, cur.fetchall())
cur.execute("select indexname,indexdef from pg_indexes where tablename in ('bf_hist_other','bf_hist_result')")
for r in cur.fetchall(): print(r[1][:150])
cur.execute("select sport,status,count(*),min(y*100+m),max(y*100+m) from bf_hist_months group by 1,2 order by 1,2")
for r in cur.fetchall(): print(r)
cur.execute("select * from bf_hist_other limit 2")
print([d[0] for d in cur.description])
for r in cur.fetchall(): print(r)
cur.execute("select * from bf_hist_result limit 3")
print([d[0] for d in cur.description])
for r in cur.fetchall(): print(r)
