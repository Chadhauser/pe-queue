import sys
sys.path.insert(0, '/root/pe-queue/runner'); import creds, psycopg2
R = psycopg2.connect(creds.pg_railway()); R.autocommit = True; r = R.cursor()
r.execute("select count(*) filter (where state='active' and now()-query_start>interval '5 minutes') from pg_stat_activity"); print('railway queries over 5 min:', r.fetchone()[0])
