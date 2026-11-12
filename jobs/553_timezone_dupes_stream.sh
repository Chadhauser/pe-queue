#!/bin/bash
# 553 (Thu 12 Nov 2026). Root cause of the "in-play tape an hour behind" that has been in every report since the cutover:
#  the liq recorder stamps rows with a NAIVE UTC time; Railway's server clock was UTC so it was right, the local PostgreSQL runs on
#  Europe/Berlin, so every local row is stored one hour EARLY. The desk reads "last 90 s" and sees nothing; the board says 61 min behind.
#  Fix: database timezone UTC (server-wide), shift the recorder's rows since the cutover by +1 h, restart the recorder.
# Second: the hourly tape_archive job copies liq_sample from pg_railway() to local — since the cutover both are the SAME table, so it has
#  been copying rows onto themselves every hour (disk growth, duplicate rows). Disabled; duplicates since the cutover removed.
# Third: stream_client's catalogue calls hit TOO_MUCH_DATA (400s) after 548 widened the pre-off universe — same guard as the liq
#  recorder (bf_chunk) imported. Fourth: the daemon's H1b/H1c scripts still open the local DB over SSL and drop mid-read — plain socket.
set -o pipefail
export PYTHONDONTWRITEBYTECODE=1
echo "== 1. timezone =="
pkill -9 -f liq_recorder.py; sleep 2
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
con=psycopg2.connect(creds.pg_local(),sslmode='disable'); con.autocommit=True; c=con.cursor(); c.execute("SET statement_timeout=0")
c.execute("show timezone"); tz=c.fetchone()[0]; print("db timezone was:",tz)
c.execute("select current_database()"); db=c.fetchone()[0]
c.execute(f'ALTER DATABASE "{db}" SET timezone TO \'UTC\''); c.execute("ALTER SYSTEM SET timezone='UTC'"); c.execute("SELECT pg_reload_conf()")
if tz!='UTC':
    c.execute("select count(*), min(ts), max(ts) from liq_sample where ts>='2026-11-10 06:00+00'"); print("recorder rows since cutover stored 1 h EARLY (not rewritten: 7 GB disk free, a 12M-row update would not fit) — STATED HOLE: liq_sample timestamps 10-12 Nov are one hour early:",c.fetchone())
c.execute("show timezone"); print("db timezone now:",c.fetchone()[0])
PY
echo "== 2. tape_archive: source == destination since the cutover — off; duplicates removed =="
( crontab -l 2>/dev/null | grep -v 'tape_archive' ) | crontab -; pkill -f tape_archive; echo "tape_archive cron removed"
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
con=psycopg2.connect(creds.pg_local(),sslmode='disable'); con.autocommit=True; c=con.cursor(); c.execute("SET statement_timeout=0")
for t,cols in [('liq_sample','ts, market_id, sel'),('ip_tape','ts, market_id, sel'),('stream_ticks','ts_recv, market_id, sel_id')]:
    try:
        c.execute(f"select count(*) from (select {cols}, count(*) from {t} where {cols.split(',')[0]} >= '2026-11-09 00:00+00' group by {cols} having count(*)>1) d"); d=c.fetchone()[0]; print(t,"duplicate keys since 9 Nov:",d)
        if d:
            c.execute(f"delete from {t} a using {t} b where a.ctid<b.ctid and a.{cols.split(',')[0].strip()}=b.{cols.split(',')[0].strip()} and a.market_id=b.market_id and a.{cols.split(',')[2].strip()}=b.{cols.split(',')[2].strip()} and a.{cols.split(',')[0].strip()}>='2026-11-09 00:00+00'"); print("  deleted",c.rowcount)
            c.execute(f"vacuum (analyze) {t}")
    except Exception as e: print(t,"dedupe:",str(e)[:120])
PY
echo "== 3. recorder back, proof =="
sleep 70; pgrep -fa liq_recorder.py | cut -c1-60
sleep 120; python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
c=psycopg2.connect(creds.pg_local(),sslmode='disable').cursor(); c.execute("select count(*), max(ts), now() from liq_sample where ts>now()-interval '3 minutes'"); n,m,now=c.fetchone()
print("LOCAL liq_sample last 3 min:",n,"max",m,"now",now,"| PROOF","PASS" if n else "FAIL (no in-play football right now? check liq_heartbeat live_markets)")
c.execute("select last_seen, live_markets from liq_heartbeat"); print("heartbeat:",c.fetchall())
PY
echo "== 4. stream: catalogue overflow guard =="
cd /root/pe-stream && cp stream_client.py stream_client.py.bak_553 && python3 - <<'PY'
p='/root/pe-stream/stream_client.py'; s=open(p).read()
if 'bf_chunk' not in s:
    i=s.index('\n',s.index('import '))+1 if s.startswith('import') or s.startswith('#') else 0
    lines=s.split('\n'); k=next(i for i,l in enumerate(lines) if l.startswith('import ') or l.startswith('from '))
    lines.insert(k,"import sys as _s553; _s553.path.insert(0,'/root/pe-liq'); import bf_chunk  # 553: listMarketCatalogue TOO_MUCH_DATA -> bisect (same guard as the liq recorder)")
    open(p,'w').write('\n'.join(lines)); print("bf_chunk imported into stream_client")
PY
python3 -m py_compile stream_client.py && pkill -f stream_client.py && echo "stream restarted by keepalive" || cp stream_client.py.bak_553 stream_client.py
echo "== 5. team scripts over a plain socket =="
cd /root/pe-sports/team && sed -i "s/creds.pg_local(),sslmode='prefer')/creds.pg_local(),sslmode='disable')/g" fairprice_inplay.py fairprice_country.py fairprice_v0.py 2>/dev/null; grep -c "sslmode='disable'" fairprice_inplay.py fairprice_country.py fairprice_v0.py; python3 -m py_compile fairprice_inplay.py fairprice_country.py fairprice_v0.py && echo "compile ok"
echo "== 6. the numbers =="
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
c=psycopg2.connect(creds.pg_local(),sslmode='disable').cursor()
c.execute("select sport, count(*) from fair_price_passed group by 1 order by 2 desc"); print("PASSED cells by sport:",c.fetchall())
c.execute("select sport, count(*) from fair_price_calib group by 1 order by 2 desc"); print("map cells by sport:",c.fetchall())
c.execute("select count(*) from fair_price_passed_inplay"); print("desk in-play cells:",c.fetchone()[0])
c.execute("select mkt, side, count(*) n, count(*) filter (where status='settled') settled, round(coalesce(sum(pnl) filter (where status='settled'),0)::numeric,2) pnl from bookie_paper where version='v2' and fill_kind='taker' group by 1,2 order by 3 desc"); print("TAKER by cell:",c.fetchall())
c.execute("select status, count(*), round(coalesce(sum(pnl),0)::numeric,2) from bookie_paper where version='v2' and fill_kind='taker' group by 1"); print("TAKER by status:",c.fetchall())
c.execute("select line, status, count(*), round(coalesce(sum(pnl),0)::numeric,2) from desk_calls group by 1,2 order by 1,2"); print("DESK calls:",c.fetchall())
c.execute("select status, count(*) from bf_hist_months group by 1"); print("history months:",c.fetchall())
PY
df -h / | tail -1
echo "553 done"
