import sys, psycopg2
sys.path.insert(0, '/root/pe-queue/runner')
import creds
con = psycopg2.connect(creds.pg_local())
c = con.cursor()
c.execute("SET statement_timeout='400s'; SET work_mem='64MB'")
c.execute("""SELECT inplay,status,count(*),count(ltp),count(tv),count(pt),min(pt),max(pt),min(secs_to_off),max(secs_to_off)
             FROM stream_ticks WHERE sport='football' AND mkt='MO' GROUP BY 1,2""")
for r in c.fetchall():
    print(r)
c.execute("""SELECT market_id FROM stream_ticks WHERE sport='football' AND mkt='MO' AND inplay LIMIT 1""")
m = c.fetchone()[0]
c.execute("""SELECT pt,inplay,status,sel,back_px,lay_px,ltp,tv,secs_to_off FROM stream_ticks WHERE market_id=%s ORDER BY pt LIMIT 12""", (m,))
for r in c.fetchall():
    print(r)
c.execute("""SELECT sport,mkt,inplay,count(*) FROM stream_ticks WHERE NOT inplay GROUP BY 1,2,3 ORDER BY 4 DESC LIMIT 10""")
print(c.fetchall())
