import sys, glob, re
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local())
k = c.cursor()
k.execute("SET statement_timeout='400s'")
def q(s):
    k.execute(s)
    return k.fetchall()
blob = ''
for f in glob.glob('jobs/*.sh'):
    blob += open(f, errors='ignore').read()
print('== ip_tape by sport, market_type')
for r in q("select sport, market_type, count(distinct market_id), count(distinct event_name), count(*), count(distinct date(ts)) from ip_tape where sport in ('basketball','american_football','rugby_union','australian_rules','ice_hockey','baseball') group by 1,2 order by 1,5 desc"):
    print(r)
print(q("select sport,count(*) from ip_tape group by 1 order by 2 desc"))
print('== basketball sample')
for r in q("select market_id, event_name, market_type, sel_name, back_px, back_sz, lay_px, lay_sz, secs_since_start from ip_tape where sport='basketball' and ts>now()-interval '12 hours' and market_type not in ('MATCH_ODDS') order by ts desc limit 12"):
    print(r)
print('== bf_hist_other market types, a week of Sep 2026')
rows = q("select sport, market_type, count(distinct market_id) from bf_hist_other where market_time>='2026-09-05' and market_time<'2026-09-08' group by 1,2 order by 1,3 desc")
for s, m, n in rows:
    print(s, m, n, 'jobs:', len(re.findall(re.escape(m), blob)))
c2 = psycopg2.connect(creds.pg_railway())
k2 = c2.cursor()
k2.execute("SET statement_timeout='60s'")
for t in ['tennis_results_2026','tennis_matches','cricket_matches','racing_results','greyhound_racecards_today']:
    k2.execute("select column_name from information_schema.columns where table_name='%s' order by ordinal_position" % t)
    print(t, [x[0] for x in k2.fetchall()])
