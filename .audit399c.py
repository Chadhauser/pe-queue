import sys,psycopg2,pandas as pd,numpy as np,time
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
pd.set_option('display.width',240); pd.set_option('display.max_columns',30)
L=psycopg2.connect(creds.pg_local()); L.autocommit=True; c=L.cursor(); c.execute("SET statement_timeout='400s'; SET work_mem='64MB'")
for tb in ('stream_ticks','liq_sample'):
    c.execute("SELECT to_regclass(%s)",(tb,)); print(tb,'local:',c.fetchone()[0])
c.execute("SELECT min(pt),max(pt),count(*) FROM stream_ticks WHERE sport='racing' AND mkt='WIN' AND inplay"); print('local racing in-play ticks',c.fetchone())
c.execute("SELECT q,d,side,count(*),min(t),max(t) FROM finder_touch_entries WHERE q IN (1.1,1.2) AND d=1 GROUP BY 1,2,3 ORDER BY 1,3"); print(c.fetchall())
# per-runner traded volume on the stream: does it ever fall? falling would mean the stream rewinds too
c.execute("""CREATE TEMP TABLE tk AS SELECT market_id,sel_id,extract(epoch from pt)::float8 t,status,inplay,tv::float8 tv,back_px::float8 back_px,lay_px::float8 lay_px FROM stream_ticks WHERE sport='racing' AND mkt='WIN' AND inplay AND tv IS NOT NULL""")
c.execute("CREATE INDEX ON tk (market_id,sel_id,t)"); c.execute("ANALYZE tk")
c.execute("""SELECT count(*),sum((d<-0.001)::int),sum((d<-0.01)::int) FROM (SELECT tv/NULLIF(max(tv) OVER (PARTITION BY market_id,sel_id ORDER BY t ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING),0)-1 d FROM tk) x WHERE d IS NOT NULL"""); print('stream racing in-play ticks with tv, falling >0.1%, falling >1%',c.fetchone())
c.execute("SELECT status,count(*) FROM tk GROUP BY 1"); print('status',c.fetchall())
# entries from item 380 that overlap the local ticks
c.execute("SELECT min(t),max(t) FROM tk"); lo,hi=c.fetchone(); print('tk range',pd.to_datetime(lo,unit='s'),pd.to_datetime(hi,unit='s'))
c.execute("""CREATE TEMP TABLE en AS SELECT market_id,sel::bigint sel_id,q,t::float8 t,px::float8 px,won,v::float8 v FROM finder_touch_entries WHERE q IN (1.1,1.2) AND d=1 AND side='B' AND t BETWEEN %s AND %s""",(lo,hi))
c.execute("""SELECT e.q,count(*),sum(CASE WHEN x.tvb IS NOT NULL AND x.tva<x.tvb*0.999 THEN 1 ELSE 0 END),sum(CASE WHEN x.tvb IS NOT NULL THEN 1 ELSE 0 END),avg(e.v) FROM en e LEFT JOIN LATERAL (SELECT max(tv) FILTER (WHERE y.t<e.t) tvb,min(tv) FILTER (WHERE y.t>=e.t AND y.t<=e.t+5) tva FROM tk y WHERE y.market_id=e.market_id AND y.sel_id=e.sel_id AND y.t BETWEEN e.t-120 AND e.t+5) x ON true GROUP BY 1 ORDER BY 1"""); print('entries: q, n, tv fell at the fill, n with tv before, mean v',c.fetchall())
# football rest feed: total matched falling in liq_sample, Railway, one recent day, MO in play
rc=psycopg2.connect(creds.pg_railway(),sslmode='require'); rc.autocommit=True; k=rc.cursor(); k.execute("SET statement_timeout='200s'")
k.execute("SELECT max(ts) FROM liq_sample WHERE ts>now()-interval '3 days'"); print('liq_sample latest',k.fetchone())
k.execute("""SELECT count(*),sum((d<-0.001)::int),sum((d<-0.01)::int) FROM (SELECT total_matched::float8/NULLIF(max(total_matched::float8) OVER (PARTITION BY market_id ORDER BY ts ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING),0)-1 d FROM liq_sample WHERE mkt='MATCH_ODDS' AND ts>=now()-interval '36 hours' AND ts<now()-interval '12 hours') x WHERE d IS NOT NULL"""); print('liq_sample football MO 36 h: rows, falling >0.1%, >1%',k.fetchone())
k.execute("""SELECT count(*),sum((d<-0.001)::int),sum((d<-0.01)::int) FROM (SELECT total_matched::float8/NULLIF(max(total_matched::float8) OVER (PARTITION BY market_id ORDER BY ts ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING),0)-1 d FROM ip_tape WHERE sport='horse_racing' AND market_type='WIN' AND status='OPEN' AND ts>=now()-interval '36 hours') x WHERE d IS NOT NULL"""); print('ip_tape racing 36 h OPEN: rows, falling >0.1%, >1%',k.fetchone())
