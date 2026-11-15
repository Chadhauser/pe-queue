import sys, time
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local())
cur = c.cursor()
cur.execute("SET statement_timeout='1200s'")
T = "('TEAM_A_1','TEAM_A_2','TEAM_A_3','TEAM_B_1','TEAM_B_2','TEAM_B_3')"
t = time.time()
cur.execute(f"""select date_trunc('month', market_time)::date, market_type, count(distinct market_id)
 from bf_hist_other where sport='Soccer' and market_type in {T} group by 1,2 order by 1,2""")
for r in cur.fetchall():
    print(r)
print('secs', round(time.time() - t))
cur.execute(f"""select event_name, market_type, sel, count(*), min(ltp), max(ltp) from bf_hist_other
 where sport='Soccer' and market_type in {T} and market_time >= '2026-09-05' and market_time < '2026-09-06'
 group by 1,2,3 order by 1,2,3 limit 24""")
for r in cur.fetchall():
    print(r)
cur.execute(f"""select o.market_type, r.status, count(*) from (select distinct market_id, market_type from bf_hist_other
 where sport='Soccer' and market_type in {T}) o left join bf_hist_result r on r.market_id=o.market_id group by 1,2 order by 1,2""")
for r in cur.fetchall():
    print('RES', r)
cur.execute(f"""select r.sel, r.status from bf_hist_result r where r.market_id in (select market_id from bf_hist_other
 where sport='Soccer' and market_type='TEAM_A_2' limit 1)""")
print(cur.fetchall())
