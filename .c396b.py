import sys,psycopg2,re
sys.path.insert(0,'/root/pe-queue/runner'); import creds
c=psycopg2.connect(creds.pg_railway(),sslmode='require'); c.autocommit=True; k=c.cursor(); k.execute("SET statement_timeout='120s'")
k.execute("SELECT sport,market_type,count(*),count(DISTINCT market_id),min(ts)::date,max(ts)::date,percentile_cont(.5) within group (order by suspended_secs) FROM ip_reopen GROUP BY 1,2 ORDER BY 3 DESC LIMIT 25")
for r in k.fetchall(): print(r)
k.execute("SELECT status,count(*) FROM (SELECT 'x' status) a GROUP BY 1")
for l in open('watchman/FINDER_QUEUE.md'):
    m=re.match(r'(\d+)\. ',l)
    if m and m.group(1) in ('177','126'): print(l[:1500]); print()
