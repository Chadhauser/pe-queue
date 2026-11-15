import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local())
cur = c.cursor()
cur.execute("SET work_mem='64MB'; SET statement_timeout='600s';")
cur.execute("""select table_name, column_name, data_type from information_schema.columns
 where table_schema='public' and (column_name ilike '%coach%' or column_name ilike '%manager%' or column_name ilike '%referee%'
   or column_name ilike '%venue%' or column_name ilike '%round%' or column_name ilike '%attend%' or column_name ilike '%weather%')
 order by 1,2""")
for r in cur.fetchall():
    print(r)
cur.execute("""select column_name, data_type from information_schema.columns where table_name='af_fixtures' order by ordinal_position""")
print([r[0] for r in cur.fetchall()])
cur.execute("""select column_name from information_schema.columns where table_name='af_lineups' order by ordinal_position""")
print([r[0] for r in cur.fetchall()])
