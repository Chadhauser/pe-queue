import sys, glob, psycopg2
sys.path.insert(0, '/root/pe-queue/runner')
import creds
text = {}
for f in glob.glob('/root/pe-queue/jobs/499*'):
    try:
        text[f.split('/')[-1]] = open(f, errors='ignore').read()
    except Exception:
        pass
c = psycopg2.connect(creds.pg_local())
cur = c.cursor()
cur.execute("""select column_name, data_type from information_schema.columns where table_name='bf_hist_other' order by ordinal_position""")
print(cur.fetchall())
cur.execute("""select column_name, data_type from information_schema.columns where table_name='bf_hist_result' order by ordinal_position""")
print(cur.fetchall())
cur.execute("""select market_type, count(*) from (select distinct market_type, market_id from bf_hist_result) x group by 1 order by 2 desc""")
res = dict(cur.fetchall())
cur.execute("""select market_type, count(distinct market_id), count(*) from bf_hist_other
               where sport='Soccer' and market_time >= '2023-09-01' and market_time < '2023-10-01'
               group by 1 order by 2 desc""")
print('== soccer market types Sep 2023; official-result markets, all months')
for mt, m, n in cur.fetchall():
    hits = [j for j, s in text.items() if mt in s]
    print(f'{mt:34s} markets {m:>7,} rows {n:>10,} results {res.get(mt, 0):>8,} 499-jobs={len(hits)}')
