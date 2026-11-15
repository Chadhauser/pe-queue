import sys, psycopg2
sys.path.insert(0, '/root/pe-queue/runner')
import creds
con = psycopg2.connect(creds.pg_local())
c = con.cursor()
c.execute("SET statement_timeout='120s'")
c.execute("select column_name,data_type from information_schema.columns where table_name='af_fixtures' order by ordinal_position")
print(c.fetchall())
c.execute("select table_name from information_schema.tables where table_schema='public' and (table_name like 'af_%' or table_name like '%coach%' or table_name like 'fd_%') order by 1")
print([r[0] for r in c.fetchall()])
c.execute("select season,count(*),min(date(kickoff)) from af_fixtures group by 1 order by 1") if False else None
c.execute("select * from af_fixtures limit 2")
print(c.fetchall())
