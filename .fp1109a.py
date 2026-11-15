import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
con = psycopg2.connect(creds.pg_local()); cur = con.cursor()
cur.execute("SET statement_timeout='600s'")
cur.execute("select table_name from information_schema.tables where table_name like 'fair_price%' order by 1")
tabs = [r[0] for r in cur.fetchall()]
print(tabs)
for t in tabs:
    cur.execute("select column_name from information_schema.columns where table_name=%s order by ordinal_position", (t,))
    cols = [r[0] for r in cur.fetchall()]
    cur.execute(f"select count(*) from {t}")
    n = cur.fetchone()[0]
    extra = ''
    if 'built_at' in cols:
        cur.execute(f"select min(built_at), max(built_at) from {t}")
        extra = cur.fetchone()
    print(t, n, cols, extra)
cur.execute("select table_name from information_schema.tables where table_name like '%hypoth%' or table_name like 'h1%' order by 1")
print(cur.fetchall())
