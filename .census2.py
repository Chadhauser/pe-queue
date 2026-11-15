import sys, glob, re
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local())
k = c.cursor()
k.execute("SET statement_timeout='300s'")
def q(s):
    k.execute(s)
    return k.fetchall()
for t in ['ip_tape','stream_ticks','liq_sample','liq_runners','racing_bsp','bf_hist_other','bf_hist_result','coach_path','goal_stats_live','fair_price_games']:
    cols = q("select column_name||':'||data_type from information_schema.columns where table_name='%s' order by ordinal_position" % t)
    print(t, [x[0] for x in cols])
print(q("select sport, count(*), min(ts), max(ts) from ip_tape group by 1 order by 2 desc limit 25"))
print(q("select min(ts_recv), max(ts_recv) from stream_ticks"))
print(q("select min(ts), max(ts) from liq_sample"))
print(q("select min(ts), max(ts), count(*) from liq_runners") if any('ts:' in x[0] for x in q("select column_name||':' from information_schema.columns where table_name='liq_runners'")) else 'liq_runners no ts')
print(q("select market_type, count(*) from stream_ticks group by 1 order by 2 desc limit 20"))
for w in ['ipmin','ipmax','liq_runners','ppmin','morningtradedvol']:
    fs = [f for f in glob.glob('jobs/*.sh') if w in open(f, errors='ignore').read()]
    print(w, len(fs), fs[:25])
