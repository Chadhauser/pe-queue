import sys,psycopg2,pandas as pd
sys.path.insert(0,'/root/pe-queue/runner'); import creds
L=psycopg2.connect(creds.pg_local()); L.autocommit=True; c=L.cursor(); c.execute("SET statement_timeout='500s'; SET work_mem='64MB'")
# counts only, no prices: reopens on the clean feed
c.execute("""SELECT sport,mkt,count(*) n,count(DISTINCT market_id) m,percentile_cont(.5) within group (order by gap_end) FROM (
 SELECT sport,mkt,market_id,pt,lag(status) OVER w ps,status,extract(epoch from (max(pt) OVER (PARTITION BY market_id,sel_id)-pt)) gap_end FROM stream_ticks WHERE inplay AND status IN ('OPEN','SUSPENDED') WINDOW w AS (PARTITION BY market_id,sel_id ORDER BY pt)) x WHERE ps='SUSPENDED' AND status='OPEN' GROUP BY 1,2 ORDER BY 3 DESC LIMIT 12""")
print('sport mkt reopen-ticks markets median secs to market end'); [print(r) for r in c.fetchall()]
# item 393's collapse: did traded volume rewind? stream, racing
c.execute("""CREATE TEMP TABLE tmp_t AS SELECT market_id,sel_id,extract(epoch from pt)::float8 t,back_px::float8 back_px,tv::float8 tv FROM stream_ticks WHERE sport='racing' AND mkt='WIN' AND inplay AND status='OPEN'""")
c.execute("CREATE INDEX ON tmp_t (market_id,sel_id,t)"); c.execute("ANALYZE tmp_t")
c.execute("""WITH f AS (SELECT DISTINCT ON (market_id,sel_id) market_id,sel_id,back_px st FROM tmp_t WHERE back_px IS NOT NULL ORDER BY market_id,sel_id,t),
 h AS (SELECT market_id,sel_id,min(t) tt FROM tmp_t WHERE back_px<=1.1 GROUP BY 1,2)
 SELECT h.market_id,h.sel_id,j.t-h.tt,j.back_px,j.tv,p.hi FROM h JOIN f USING (market_id,sel_id) JOIN LATERAL (SELECT x.t,x.back_px,x.tv FROM tmp_t x WHERE x.market_id=h.market_id AND x.sel_id=h.sel_id AND x.t>h.tt AND x.t<=h.tt+120 AND x.back_px>=2.0 ORDER BY x.t LIMIT 1) j ON true
 LEFT JOIN LATERAL (SELECT max(y.tv) hi FROM tmp_t y WHERE y.market_id=h.market_id AND y.sel_id=h.sel_id AND y.t<j.t) p ON true WHERE f.st>1.1""")
R=c.fetchall(); print('collapses on the stream, tv at the row v earlier high',len(R)); [print(r) for r in R[:15]]
