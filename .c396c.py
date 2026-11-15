import sys,psycopg2,pandas as pd
sys.path.insert(0,'/root/pe-queue/runner'); import creds
# timing only, no prices: when do racing and tennis reopens happen, and how many markets join results
c=psycopg2.connect(creds.pg_railway(),sslmode='require'); c.autocommit=True; k=c.cursor(); k.execute("SET statement_timeout='180s'")
k.execute("""SELECT sport,width_bucket(secs_since_start,-300,900,12) b,count(*),count(DISTINCT market_id),count(DISTINCT ts) FROM ip_reopen WHERE sport IN ('horse_racing','racing') AND market_type='WIN' GROUP BY 1,2 ORDER BY 1,2""")
for r in k.fetchall(): print(r)
k.execute("SELECT count(DISTINCT market_id),min(ts),max(ts) FROM ip_reopen WHERE sport='horse_racing' AND market_type='WIN' AND competition IS NOT NULL")
print(k.fetchone())
k.execute("SELECT competition,count(DISTINCT market_id) FROM ip_reopen WHERE sport='horse_racing' AND market_type='WIN' GROUP BY 1 ORDER BY 2 DESC LIMIT 6"); print(k.fetchall())
k.execute("SELECT split_part(event_name,' ',1),count(DISTINCT market_id) FROM ip_reopen WHERE sport='horse_racing' AND market_type='WIN' GROUP BY 1 ORDER BY 2 DESC LIMIT 12"); print(k.fetchall())
k.execute("SELECT count(DISTINCT market_id) FROM ip_reopen WHERE sport='horse_racing' AND market_type='WIN' AND market_id IN (SELECT market_id FROM racing_results)"); print('joined to racing_results',k.fetchone())
k.execute("SELECT min(ts),max(ts) FROM racing_results") if False else None
k.execute("SELECT column_name FROM information_schema.columns WHERE table_name='racing_results' ORDER BY ordinal_position"); print([x[0] for x in k.fetchall()])
k.execute("SELECT width_bucket(n,0,15,5),count(*) FROM (SELECT market_id,count(DISTINCT ts) n FROM ip_reopen WHERE sport='horse_racing' AND market_type='WIN' GROUP BY 1) x GROUP BY 1 ORDER BY 1"); print('reopens per market',k.fetchall())
