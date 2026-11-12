#!/bin/bash
# 554 (Thu 12 Nov 2026, 14:00). DISK EMERGENCY: 4.9 GB free. PostgreSQL stops when it hits zero and takes every recorder with it.
# Deleting rows does not give disk back (dead tuples); VACUUM FULL needs a table's size in free space. So:
#  1. Non-database space: journal, apt cache, pip cache, temp downloads, old logs.
#  2. Tables the fair-price bot does not need (the ARCHIVE class from inventory/2026-11-09.md): compressed dump to /root/pe-archive/tables/
#     then DROP — a drop returns space immediately; the dump can be restored with zstdcat | psql.
#  3. The three live tapes: keep the last 5 days by REBUILD-AND-SWAP (new table from the recent rows, indexes, rename), which needs only the
#     recent rows' space, not the whole table's. Older rows are already in /root/pe-archive/<table>/<day>.csv.zst from 548/552 (checked
#     here first: a day without its file is archived before the swap). Recorders paused for the seconds the swap takes.
#  Every step prints df before and after.
set -o pipefail
export PYTHONDONTWRITEBYTECODE=1
echo "== 0. where is the space =="; df -h / | tail -1; du -xsh /root/* 2>/dev/null | sort -rh | head -12; du -sh /var/log /var/lib/postgresql 2>/dev/null
echo "== 1. non-database =="
journalctl --vacuum-size=200M >/dev/null 2>&1; apt-get clean >/dev/null 2>&1; rm -rf /root/.cache/pip /root/pe-hist/.adv.bz2 /root/pe-hist/*.bz2 /root/pe-migrate/.d_*.tsv 2>/dev/null
find /root -maxdepth 3 -type f -name '*.log' -size +200M -printf '%s %p\n' 2>/dev/null | sort -rn | head -10 | while read sz p; do echo "truncating $p ($((sz/1000000)) MB)"; tail -c 20000000 "$p" > "$p.tmp" && mv "$p.tmp" "$p"; done
find /root/pe-queue-logs -type f -mtime +14 -delete 2>/dev/null
df -h / | tail -1
echo "== 2. dump + drop tables the bot does not need =="
mkdir -p /root/pe-archive/tables
python3 - <<'PY'
import sys, re, subprocess, os; sys.path.insert(0,'/root/pe-queue/runner'); import creds, psycopg2
KEEP=r'^(bf_hist|racing_bsp|liq_sample$|liq_runners|liq_heartbeat|liq_goal_depth|stream_ticks$|stream_heartbeat|xx_tape$|ip_tape$|fair_price|bookie_paper|bookie_heartbeat|integrity|job_results|desk_calls|paper_ledger|edge$|delete_trap|watchdog_log)'
con=psycopg2.connect(creds.pg_local(),sslmode='disable'); con.autocommit=True; c=con.cursor(); c.execute("SET statement_timeout=0")
c.execute("SELECT schemaname, tablename, pg_total_relation_size(quote_ident(schemaname)||'.'||quote_ident(tablename)) FROM pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema') ORDER BY 3 DESC")
freed=0
for sch,t,sz in c.fetchall():
    if sch=='public' and re.search(KEEP,t): continue
    if sz<100e6: continue
    f=f"/root/pe-archive/tables/{sch}.{t}.sql.zst"
    r=subprocess.run(f"pg_dump --no-owner -t '{sch}.\"{t}\"' '{creds.pg_local()}' | zstd -q -T2 -f -o '{f}'",shell=True)
    if r.returncode==0 and os.path.getsize(f)>0:
        c.execute(f'DROP TABLE "{sch}"."{t}"'); freed+=sz; print(f"dropped {sch}.{t} {sz/1e9:.1f} GB -> {f} ({os.path.getsize(f)/1e6:.0f} MB)")
    else: print(f"dump failed for {sch}.{t} — kept")
print(f"freed from drops: {freed/1e9:.1f} GB")
PY
df -h / | tail -1
echo "== 3. rebuild-and-swap the live tapes to the last 5 days =="
pkill -9 -f liq_recorder.py; pkill -9 -f stream_client.py; pkill -9 -f xx_recorder; pkill -9 -f ip_recorder; pkill -f bookie_v2.py; pkill -f desk.py; pkill -f sports_team.py; sleep 2
KEEP_DAYS=5 timeout 3000 python3 /root/pe-archive/archive_tape.py | tail -5   # any day older than 5 days not yet in a file goes to one (and its rows are deleted) before the swap
python3 - <<'PY'
import sys, time; sys.path.insert(0,'/root/pe-queue/runner'); import creds, psycopg2, shutil
con=psycopg2.connect(creds.pg_local(),sslmode='disable'); con.autocommit=True; c=con.cursor(); c.execute("SET statement_timeout=0; SET maintenance_work_mem='256MB'")
for t,col in [('xx_tape','ts'),('liq_sample','ts'),('ip_tape','ts'),('stream_ticks','ts_recv')]:
    c.execute(f"SELECT pg_total_relation_size('{t}')/1e9, (SELECT count(*) FROM \"{t}\" WHERE \"{col}\">now()-interval '5 days')"); size,recent=c.fetchone()
    free=shutil.disk_usage('/').free/1e9
    c.execute(f'SELECT count(*) FROM "{t}"'); total=c.fetchone()[0]
    need=size*recent/max(1,total)*1.3
    print(f"{t}: {size:.1f} GB, rows {total}, last 5 days {recent}, rebuild needs ~{need:.1f} GB, free {free:.1f} GB",flush=True)
    if need>free-1.0: print(f"  skipped: not enough free disk for the rebuild — next pass after the other tables are done"); continue
    c.execute(f'SELECT indexdef FROM pg_indexes WHERE tablename=%s',(t,)); idx=[d[0] for d in c.fetchall()]
    t0=time.time()
    c.execute(f'CREATE TABLE "{t}__new" (LIKE "{t}" INCLUDING DEFAULTS)')
    c.execute(f'INSERT INTO "{t}__new" SELECT * FROM "{t}" WHERE "{col}">now()-interval \'5 days\'')
    c.execute(f'DROP TABLE "{t}"'); c.execute(f'ALTER TABLE "{t}__new" RENAME TO "{t}"')
    for d in idx:
        try: c.execute(d)   # same table name after the rename; the old indexes went with the old table
        except Exception as e: print("  index",str(e)[:80])
    c.execute(f'ANALYZE "{t}"'); print(f"  rebuilt in {time.time()-t0:.0f}s; free now {shutil.disk_usage('/').free/1e9:.1f} GB",flush=True)
PY
nohup /root/pe-sports/team/run_team.sh >/dev/null 2>&1 & disown; nohup /root/pe-sports/desk/run_desk.sh >/dev/null 2>&1 & disown
sleep 90; echo "recorders back: $(pgrep -fa 'liq_recorder|stream_client|xx_recorder|ip_recorder|bookie_v2|desk.py|sports_team' | wc -l) processes"; df -h / | tail -1
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
c=psycopg2.connect(creds.pg_local(),sslmode='disable').cursor()
for t,col in [('liq_sample','ts'),('stream_ticks','ts_recv'),('xx_tape','ts'),('ip_tape','ts')]:
    c.execute(f'select count(*) from "{t}" where "{col}">now()-interval \'2 minutes\''); print("LOCAL",t,"last 2 min:",c.fetchone()[0])
c.execute("select pg_database_size(current_database())/1e9"); print("database GB:",round(c.fetchone()[0],1))
PY
echo "554 done"
