#!/bin/bash
# 355: PERMANENT TAPE. Something prunes liq_sample / ip_tape / stream_ticks on Railway after ~6 days (3.4M / 5.2M / 26M rows
# deleted since 3 Nov 19:30 per pg_stat). Until the pruner is found (a delete trap is now on those tables), copy the tape
# hourly into the local Postgres, append-only: tables liq_sample, ip_tape, stream_ticks, player_liq (same columns) with a
# watermark per table. First run backfills whatever still exists on Railway. Installed as an hourly cron (:05), log in /root/pe-data.
set -o pipefail
mkdir -p /root/pe-data
cat > /root/pe-data/tape_archive.py <<'PY'
import sys, io, time, psycopg2
sys.path.insert(0,'/root/pe-queue/runner'); import creds
R=psycopg2.connect(creds.pg_railway(), sslmode='require'); R.autocommit=True; rc=R.cursor(); rc.execute("SET statement_timeout='900s'")
L=psycopg2.connect(creds.pg_local()); L.autocommit=True; lc=L.cursor()
lc.execute("CREATE TABLE IF NOT EXISTS tape_archive_wm (tbl TEXT PRIMARY KEY, wm TIMESTAMPTZ, rows BIGINT DEFAULT 0, updated TIMESTAMPTZ)")
TABLES=[('liq_sample','ts'),('ip_tape','ts'),('stream_ticks','ts_recv'),('player_liq','ts')]
for t,tsc in TABLES:
    rc.execute("select to_regclass(%s) is not null",(t,))
    if not rc.fetchone()[0]: print(t,"not on railway"); continue
    rc.execute("select string_agg(column_name||' '||data_type, ', ' order by ordinal_position), string_agg(column_name, ',' order by ordinal_position) from information_schema.columns where table_name=%s",(t,))
    ddl,cols=rc.fetchone()
    lc.execute(f"CREATE TABLE IF NOT EXISTS {t} ({ddl})")
    lc.execute(f"CREATE INDEX IF NOT EXISTS {t}_arch_ts ON {t} ({tsc})")
    lc.execute("select wm from tape_archive_wm where tbl=%s",(t,)); r=lc.fetchone(); wm=r[0] if r else None
    # copy in 1-hour slices from the watermark (or the oldest row on railway), stopping 2 min short of now
    rc.execute(f"select min({tsc}), max({tsc}) from {t}"); mn,mx=rc.fetchone()
    if mn is None: print(t,"empty on railway"); continue
    start=wm or mn; t0=time.time(); total=0
    while start < mx:
        end=start+__import__('datetime').timedelta(hours=1)
        buf=io.StringIO()
        rc.copy_expert(f"COPY (SELECT {cols} FROM {t} WHERE {tsc} > %s AND {tsc} <= %s) TO STDOUT" % (psycopg2.extensions.adapt(start).getquoted().decode(), psycopg2.extensions.adapt(end).getquoted().decode()), buf)
        n=buf.getvalue().count('\n'); buf.seek(0)
        if n: lc.copy_expert(f"COPY {t} ({cols}) FROM STDIN", buf)
        total+=n; start=end
        lc.execute("INSERT INTO tape_archive_wm VALUES (%s,%s,%s,now()) ON CONFLICT (tbl) DO UPDATE SET wm=EXCLUDED.wm, rows=tape_archive_wm.rows+EXCLUDED.rows, updated=now()",(t,min(end,mx),n))
        if time.time()-t0>2400: print(t,"time budget, continues next hour"); break
    lc.execute(f"select count(*), min({tsc}), max({tsc}) from {t}"); print(t, "copied", total, "local now", lc.fetchone(), flush=True)
PY
python3 -m py_compile /root/pe-data/tape_archive.py || exit 1
( crontab -l 2>/dev/null | grep -v tape_archive; echo "5 * * * * cd /root/pe-data && flock -n /root/pe-data/.arch.lock python3 tape_archive.py >> archive.log 2>&1" ) | crontab -
echo "== first run (backfill, may take a while)"; cd /root/pe-data && timeout 3000 python3 tape_archive.py 2>&1 | tail -8
echo "== disk"; df -h / | tail -1
