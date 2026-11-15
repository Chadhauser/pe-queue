import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
con = psycopg2.connect(creds.pg_local()); cur = con.cursor()
cur.execute("SET statement_timeout='600s'")
for t in ('bf_hist_other', 'bf_hist_result', 'bf_hist_other_files'):
    cur.execute("select indexdef from pg_indexes where tablename=%s", (t,))
    print(t, [r[0] for r in cur.fetchall()])
cur.execute("select pg_size_pretty(pg_total_relation_size('bf_hist_other'))")
print(cur.fetchone())
cur.execute("select count(*), count(distinct market_type) from fair_price_passed where source='H1'")
print('passed', cur.fetchone())
cur.execute("select market_type, band_lo, band_hi, side, n_is, n_oos, edge_is, edge_oos, passed_at from fair_price_passed where source='H1' order by 1,2")
for r in cur.fetchall(): print(r)
