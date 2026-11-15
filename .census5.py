import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local())
k = c.cursor()
k.execute("SET statement_timeout='300s'")
def q(s):
    k.execute(s)
    return k.fetchall()
print(q("select indexdef from pg_indexes where tablename='ip_tape'"))
print(q("select event_id, event_name, market_id, market_time from bf_hist_other where sport='Horse Racing' and market_type='WIN' and country='GB' and market_time>='2026-08-15' and market_time<'2026-08-16' group by 1,2,3,4 order by 1,4 limit 14"))
print(q("select market, event_id, menu_hint, event_name, event_dt, selection_name, win_lose, bsp, ipmin, ipmax, ip_vol from racing_bsp where market='win' and event_dt>='2026-08-15' and event_dt<'2026-08-16' limit 4"))
print(q("select market, win_lose, count(*), avg(bsp), sum((ipmin is null)::int), sum((ipmin<1.1)::int), sum((ipmax>100)::int) from racing_bsp group by 1,2 order by 1,2"))
print(q("select min(event_dt), max(event_dt), count(distinct event_id) from racing_bsp where market='win'"))
print(q("select status,count(*) from ip_tape where market_id in (select market_id from ip_tape where market_type='HANDICAP' and sport='basketball' limit 1) group by 1"))
# frame spacing and row order for two markets
m = q("select market_id from ip_tape where market_type='COMBINED_TOTAL' and sport='basketball' and ts>now()-interval '30 hours' limit 1")[0][0]
r = q("select ts, sel_id, back_px, lay_px, status, secs_since_start, ctid::text from ip_tape where market_id='%s' order by ts, ctid limit 26" % m)
for x in r: print(x)
