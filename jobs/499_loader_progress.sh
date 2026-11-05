#!/bin/bash
# Finder item 70: loader progress line, read-only, safe to run on every run. Local DB only. No secrets printed.
# bf_hist_months.updated is only written at the END of a month, so "stuck" is judged on the file log, not on that column alone.
set -o pipefail
python3 - <<'PY'
import sys, shutil, datetime, re
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local()); cur = c.cursor()
cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
print("== months by sport and status (bf_hist_months)")
cur.execute("""select sport,status,count(*),min(y*100+m),max(y*100+m),sum(files),sum(loaded),max(updated)::timestamp(0)
               from bf_hist_months group by 1,2 order by 1,2""")
for r in cur.fetchall(): print(' ', *r)
print("== months not DONE/EMPTY, stale over 6 h (no error text is stored in the table)")
cur.execute("""select sport,y,m,status,files,loaded,updated::timestamp(0),round(extract(epoch from now()-updated)/3600) from bf_hist_months
               where status not in ('DONE','DONE_PRICE','EMPTY') and now()-updated>interval '6 hours' order by 1,2,3""")
rows = cur.fetchall()
for r in rows: print('  STALE', *r)
print('  stale months:', len(rows))
print("== file log, last 24 h")
cur.execute("""select count(*),max(loaded_at)::timestamp(0),count(*) filter (where loaded_at>now()-interval '1 hour') from bf_hist_other_files
               where loaded_at>now()-interval '24 hours'""")
n24, last, n1 = cur.fetchone(); print(f"  files last 24 h {n24:,}; last hour {n1:,}; newest {last}")
cur.execute("""select split_part(path,'/',5)||'-'||split_part(path,'/',6),count(*) from bf_hist_other_files
               where loaded_at>now()-interval '24 hours' group by 1 order by 2 desc""")
print('  by path month:', cur.fetchall())
print("== rows by sport and market_type (top 12 per sport; market_time range)")
cur.execute("""select sport,market_type,count(*),count(distinct market_id),min(market_time)::date,max(market_time)::date
               from bf_hist_other group by 1,2""")
rows = cur.fetchall()
by = {}
for r in rows: by.setdefault(r[0], []).append(r[1:])
tot = 0
for s, v in sorted(by.items()):
    v.sort(key=lambda x: -x[1]); sr = sum(x[1] for x in v); tot += sr
    print(f"  {s}: {sr:,} rows, {sum(x[2] for x in v):,} markets, {len(v)} market types, {min(x[3] for x in v)} to {max(x[4] for x in v)}")
    for x in v[:12]: print(f"     {x[0]} rows {x[1]:,} markets {x[2]:,} {x[3]} to {x[4]}")
print(f"  total rows {tot:,}")
print("== soccer Match Odds markets per month: the months a test can really use")
cur.execute("""select to_char(market_time,'YYYY-MM'),count(distinct market_id),count(distinct market_type) from bf_hist_other
               where sport='Soccer' and market_type='MATCH_ODDS' group by 1 order by 1""")
for r in cur.fetchall(): print(' ', r[0], r[1])
u = shutil.disk_usage('/root'); print(f"== disk free {u.free/1e9:.0f} GB")
cur.execute("select pg_size_pretty(pg_database_size(current_database()))"); print('== local DB', cur.fetchone()[0])
print("== loader log")
L = open('/root/pe-hist/loader.log', errors='replace').readlines()
for l in [x.rstrip()[:160] for x in L if re.match(r'(months still|Soccer|\s+Soccer|Horse|Tennis|WAITING|LIST)', x)][-4:]: print(' ', l)
print(' ', L[-1].rstrip()[:160])
print("== SURVIVORS: not a price test, none")
PY
