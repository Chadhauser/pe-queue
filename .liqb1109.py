import sys,psycopg2
sys.path.insert(0,'/root/pe-queue/runner'); import creds
con=psycopg2.connect(creds.pg_local()); cur=con.cursor()
cur.execute("SET work_mem='64MB'; SET statement_timeout='600s'")
cur.execute("SELECT min(ts),max(ts) FROM liq_sample WHERE mkt='BTTS'")
print('BTTS span',cur.fetchone())
cur.execute("""SELECT count(DISTINCT market_id), count(*), sum((minute>0)::int), count(DISTINCT event_name)
  FROM liq_sample WHERE mkt='BTTS' AND ts>=now()-interval '30 days'""")
print('BTTS markets, rows, in-play rows, events',cur.fetchone())
cur.execute("""SELECT DISTINCT sel FROM liq_sample WHERE mkt='BTTS' AND ts>=now()-interval '3 days' LIMIT 10""")
print('sels',cur.fetchall())
cur.execute("""SELECT percentile_cont(array[0.1,0.5,0.9]) WITHIN GROUP (ORDER BY d) FROM (
  SELECT extract(epoch FROM ts-lag(ts) OVER (PARTITION BY market_id,sel ORDER BY ts)) d FROM liq_sample
  WHERE mkt='BTTS' AND minute>0 AND ts>=now()-interval '2 days') q WHERE d IS NOT NULL""")
print('in-play BTTS row gap s, p10/50/90',cur.fetchone())
