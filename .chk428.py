import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds, psycopg2
con=psycopg2.connect(creds.pg_local()); cur=con.cursor()
for t in ('fd_matches','bf_hist_other','bf_hist_result'):
    cur.execute("select column_name,data_type from information_schema.columns where table_name=%s order by ordinal_position",(t,))
    print(t, cur.fetchall())
cur.execute("select date from fd_matches limit 1"); print(type(cur.fetchone()[0]))
