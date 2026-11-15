import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local())
cur = c.cursor()
cur.execute("SET statement_timeout='120s'")
cur.execute("""select table_name, string_agg(column_name||':'||data_type, ', ' order by ordinal_position)
 from information_schema.columns where table_schema='public' and table_name in
 ('af_fixtures','af_events','af_stats','af_lineups','af_price_map','bf_hist_other','bf_hist_result','racing_bsp','af_player_stats')
 group by 1""")
for r in cur.fetchall():
    print(r[0], '|', r[1][:900])
cur.execute("select relname, n_live_tup from pg_stat_user_tables order by n_live_tup desc limit 60")
print([(a, b) for a, b in cur.fetchall()])
