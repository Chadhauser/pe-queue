import sys, psycopg2
sys.path.insert(0, '/root/pe-queue/runner')
import creds
c = psycopg2.connect(creds.pg_local())
cur = c.cursor()
for t in ('af_fixtures', 'af_player_stats', 'af_lineups', 'liq_runners', 'racing_bsp'):
    cur.execute("select column_name from information_schema.columns where table_name=%s order by ordinal_position", (t,))
    print(t, [r[0] for r in cur.fetchall()])
cur.execute("select count(*), min(fixture_date), max(fixture_date) from af_player_stats") if False else None
cur.execute("select table_name from information_schema.tables where table_schema='public' and table_name ilike '%form%' or table_name ilike '%jock%' or table_name ilike '%train%' or table_name ilike '%racecard%'")
print(cur.fetchall())
c2 = psycopg2.connect(creds.pg_railway(), connect_timeout=20)
cu2 = c2.cursor()
cu2.execute("SET statement_timeout='120s'")
cu2.execute("select table_name, column_name from information_schema.columns where table_name in ('racing_form_features','racing_results') order by 1, ordinal_position")
print(cu2.fetchall())
cu2.execute("select reltuples::bigint from pg_class where relname='racing_form_features'")
print(cu2.fetchall())
