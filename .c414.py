import sys, psycopg2
sys.path.insert(0, '/root/pe-queue/runner')
import creds
con = psycopg2.connect(creds.pg_local())
c = con.cursor()
c.execute("SET statement_timeout='300s'; SET work_mem='64MB'")
c.execute("""SELECT relname, reltuples::bigint FROM pg_class WHERE relkind IN ('r','p') AND relname ~ 'stream|tick|liq_sample|ip_tape' ORDER BY 2 DESC LIMIT 15""")
print(c.fetchall())
for t in ('stream_ticks',):
    c.execute("SELECT column_name FROM information_schema.columns WHERE table_name=%s ORDER BY ordinal_position", (t,))
    print(t, [r[0] for r in c.fetchall()])
# item 414: the 24 touch rows
c.execute("""
WITH f AS (SELECT DISTINCT ON (market_id,sel) market_id,event_name,sel,minute,ts,ltp::float8 ltp,back_px::float8 b,lay_px::float8 l FROM liq_sample WHERE mkt='MO' AND minute>=1 ORDER BY market_id,sel,ts),
     g AS (SELECT market_id,min(ts) t1 FROM f GROUP BY 1),
     p AS (SELECT DISTINCT ON (s.market_id,s.sel) s.market_id,s.sel,s.ts,s.ltp::float8 pre FROM liq_sample s JOIN g ON g.market_id=s.market_id WHERE s.mkt='MO' AND s.minute=0 AND s.ltp>=1.01 AND s.ltp<1000 AND s.ts<=g.t1-interval '120 seconds' ORDER BY s.market_id,s.sel,s.ts DESC),
     e AS (SELECT DISTINCT ON (market_id,sel) market_id,sel,ltp::float8 lastp,minute lastmin FROM liq_sample WHERE mkt='MO' AND ltp>=1.01 AND ltp<1000 ORDER BY market_id,sel,ts DESC)
SELECT f.event_name,f.sel,f.minute,round(extract(epoch from f.ts-p.ts)) age,p.pre,f.ltp,f.b,f.l,round((100*(1/p.pre-1/f.ltp))::numeric,2) gap,e.lastp,e.lastmin
FROM f JOIN p USING(market_id,sel) JOIN e USING(market_id,sel)
WHERE f.minute BETWEEN 1 AND 3 AND f.b>=1.01 AND f.l>f.b AND 100*(1/p.pre-1/f.ltp)>=2 AND 100*(1/p.pre-1/f.ltp)<4 ORDER BY f.ts""")
rows = c.fetchall()
print(len(rows))
for r in rows:
    print(r)
