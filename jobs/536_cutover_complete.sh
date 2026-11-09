#!/bin/bash
# 536 (Mon 9 Nov 2026, 06:30). Finish what 535 half-did. 535's copier was killed after xx_tape (memory), then creds.pg_railway() was
# switched to LOCAL anyway: the bots, daemon and archive read a tape that stopped at 15:03 while the recorders (which take their DSN from
# /root/pe-bot/bot_core.py, not creds) kept writing Railway. Nothing lost on Railway; the local view went stale.
# This job: (1) puts creds back to Railway FIRST so everything is consistent again within a minute; (2) installs a generic sync that
# brings EVERY Railway table across (whole copy if missing locally, time-column delta if held) and runs it to completion now, then
# hourly; (3) does the real cutover in ONE step: creds.pg_railway() AND bot_core.DB -> local, writers restarted; (4) proves the recorders
# write locally within 5 minutes, and if liq_sample or stream_ticks show nothing, reverts BOTH switches itself. No Peter step.
set -o pipefail
export PYTHONDONTWRITEBYTECODE=1
RUN=/root/pe-queue/runner; MIG=/root/pe-migrate; mkdir -p $MIG
echo "== 1. consistency first: creds back to Railway =="
if grep -q 'pg_railway_remote' $RUN/creds.py; then cp $RUN/creds.py.bak_535 $RUN/creds.py && echo "creds reverted to Railway (bak_535)"; else echo "creds already Railway"; fi
python3 -c "import sys; sys.path.insert(0,'$RUN'); import creds; d=creds.pg_railway(); print('pg_railway() now remote:', 'rlwy' in d or 'railway' in d)"
pkill -f 'bookie_paper.py'; pkill -f 'bookie_xx.py'; pkill -f 'sports_team.py'; sleep 2; nohup /root/pe-sports/team/run_team.sh >/dev/null 2>&1 & disown
echo "bots and daemon restarted on Railway"
echo "== 2. generic sync Railway -> local (whole if missing, delta if held), streamed through files =="
cat > $MIG/sync_railway.py <<'PY'
# sync_railway (536): every public table on Railway -> local. Missing locally: pg_dump|psql (schema+data). Held locally with a time
# column: COPY rows newer than the local max, via a temp file (no table is ever held in memory). Held with a primary key and no time
# column: merge with ON CONFLICT DO NOTHING. Otherwise left alone and said so. Safe to run every hour; nothing on Railway is changed.
import sys, os, time, datetime, subprocess, psycopg2
sys.path.insert(0,'/root/pe-queue/runner'); import creds
REMOTE=os.environ.get('RAILWAY_DSN') or (creds.pg_railway_remote() if hasattr(creds,'pg_railway_remote') else creds.pg_railway())
LOCAL=creds.pg_local(); assert ('rlwy' in REMOTE or 'railway' in REMOTE) and REMOTE!=LOCAL, "remote DSN is not Railway"
R=psycopg2.connect(REMOTE,sslmode='require',connect_timeout=20); R.autocommit=True; rc=R.cursor(); rc.execute("SET statement_timeout=0")
L=psycopg2.connect(LOCAL,sslmode='prefer'); L.autocommit=True; lc=L.cursor(); lc.execute("SET statement_timeout=0")
TS=('ts','ts_recv','sent_at','created_at','placed_at','started','run_at','logged_at','seen_at','tape_date','at')
BIG=set(sys.argv[1].split(',')) if len(sys.argv)>1 and sys.argv[1] else set()   # tables to skip this pass (e.g. the tapes while a full copy runs)
rc.execute("SELECT tablename, pg_total_relation_size(quote_ident(tablename)) FROM pg_tables WHERE schemaname='public' ORDER BY 2"); tabs=rc.fetchall()
lc.execute("SELECT tablename FROM pg_tables WHERE schemaname='public'"); have={t for (t,) in lc.fetchall()}
def cols(cur,t): cur.execute("SELECT column_name FROM information_schema.columns WHERE table_schema='public' AND table_name=%s ORDER BY ordinal_position",(t,)); return [c for (c,) in cur.fetchall()]
log=open('/root/pe-migrate/sync.log','a'); T0=time.time(); err=0
for t,size in tabs:
    if t in BIG: continue
    t0=time.time(); note=''
    try:
        if t not in have:
            p1=subprocess.Popen(['pg_dump','--no-owner','--no-privileges','--no-comments','-t',f'public.{t}',REMOTE],stdout=subprocess.PIPE,stderr=subprocess.DEVNULL)
            subprocess.run(['psql','-q','-v','ON_ERROR_STOP=0',LOCAL],stdin=p1.stdout,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL); p1.wait()
            lc.execute(f'SELECT count(*) FROM "{t}"'); note=f"NEW rows {lc.fetchone()[0]}"; have.add(t)
        else:
            rn=cols(rc,t); ln=set(cols(lc,t)); common=[c for c in rn if c in ln]; collist=','.join(f'"{c}"' for c in common)
            tscol=next((c for c in TS if c in common),None)
            if not common: note='SKIP no common columns'
            elif tscol:
                lc.execute(f'SELECT max("{tscol}") FROM "{t}"'); mx=lc.fetchone()[0]
                sql=rc.mogrify(f'COPY (SELECT {collist} FROM "{t}" WHERE "{tscol}" > %s) TO STDOUT',(mx,)).decode() if mx is not None else f'COPY (SELECT {collist} FROM "{t}") TO STDOUT'
                tmp=f'/root/pe-migrate/.d_{t}.tsv'
                with open(tmp,'w') as f: rc.copy_expert(sql,f)
                n=0
                with open(tmp) as f:
                    for _ in f: n+=1
                with open(tmp) as f: lc.copy_expert(f'COPY "{t}" ({collist}) FROM STDIN',f)
                os.remove(tmp); note=f"DELTA +{n} since {str(mx)[:19]}"
            else:
                rc.execute("SELECT a.attname FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid=%s::regclass AND i.indisprimary",(f'public."{t}"',)); pk=[c for (c,) in rc.fetchall()]
                if pk and all(c in common for c in pk):
                    tmp=f'/root/pe-migrate/.d_{t}.tsv'
                    with open(tmp,'w') as f: rc.copy_expert(f'COPY (SELECT {collist} FROM "{t}") TO STDOUT',f)
                    lc.execute(f'CREATE TEMP TABLE _m AS SELECT {collist} FROM "{t}" WITH NO DATA')
                    with open(tmp) as f: lc.copy_expert(f'COPY _m ({collist}) FROM STDIN',f)
                    lc.execute(f'INSERT INTO "{t}" ({collist}) SELECT {collist} FROM _m ON CONFLICT DO NOTHING'); note=f"MERGE +{lc.rowcount}"; lc.execute('DROP TABLE _m'); os.remove(tmp)
                else: note='LEFT (no time column, no pk)'
    except Exception as e:
        note=f"ERROR {str(e)[:140]!r}"; err+=1
        try: lc.execute('DROP TABLE IF EXISTS _m')
        except Exception: pass
    line=f"{t:36s} {size/1e6:9.1f}MB {time.time()-t0:5.0f}s {note}"; print(line,flush=True); log.write(datetime.datetime.utcnow().isoformat()+' '+line+'\n')
print(f"sync done: {len(tabs)} tables, errors {err}, {(time.time()-T0)/60:.1f} min",flush=True)
PY
python3 -m py_compile $MIG/sync_railway.py && echo "sync compiles"
echo "-- full pass now (all tables) --"; timeout 9000 python3 $MIG/sync_railway.py
( crontab -l 2>/dev/null | grep -v 'pe-migrate/pull_remote.py\|pe-migrate/sync_railway.py'; echo "7 * * * * timeout 3000 /usr/bin/python3 /root/pe-migrate/sync_railway.py >> /root/pe-migrate/sync.cron.log 2>&1" ) | crontab -; echo "hourly sync installed (:07), old pull_remote removed"
echo "== 3. local SSL for writers that pass sslmode=require =="
python3 -c "import sys,psycopg2; sys.path.insert(0,'$RUN'); import creds; psycopg2.connect(creds.pg_local(),sslmode='require',connect_timeout=10).close(); print('local sslmode=require OK')" || { echo "local refuses sslmode=require — cutover NOT done; sync keeps local fresh hourly; fix SSL in the next job"; exit 0; }
echo "== 4. cutover in one step: creds + bot_core -> local, writers restarted =="
cp /root/pe-bot/bot_core.py /root/pe-bot/bot_core.py.bak_536
cat > $MIG/cut_local.sh <<'SH'
#!/bin/bash
RUN=/root/pe-queue/runner
grep -q 'pg_railway_remote' $RUN/creds.py || printf "\n# 536: trading database now local; Railway kept as pg_railway_remote() for the hourly sync\npg_railway_remote = pg_railway\ndef pg_railway(): return pg_local()\n" >> $RUN/creds.py
grep -q 'DB_RAILWAY' /root/pe-bot/bot_core.py || printf "\n# 536: recorders write the local database; Railway DSN kept as DB_RAILWAY\nDB_RAILWAY = DB\nimport sys as _s536; _s536.path.insert(0,'/root/pe-queue/runner'); import creds as _c536; DB = _c536.pg_local()\n" >> /root/pe-bot/bot_core.py
python3 -m py_compile /root/pe-bot/bot_core.py $RUN/creds.py || exit 1
pkill -f 'liq_recorder.py'; pkill -f 'stream_client'; pkill -f 'xx_recorder'; pkill -f 'player_recorder'; pkill -f 'ip_recorder|ip_tape'; pkill -f 'bookie_paper.py'; pkill -f 'bookie_xx.py'; pkill -f 'sports_team.py'; pkill -f 'integrity.py'
sleep 2; nohup /root/pe-sports/team/run_team.sh >/dev/null 2>&1 & disown
echo "cut to local at $(date -u +%H:%M:%S)"
SH
cat > $MIG/cut_back.sh <<'SH'
#!/bin/bash
cp /root/pe-queue/runner/creds.py.bak_535 /root/pe-queue/runner/creds.py; cp /root/pe-bot/bot_core.py.bak_536 /root/pe-bot/bot_core.py
pkill -f 'liq_recorder.py'; pkill -f 'stream_client'; pkill -f 'xx_recorder'; pkill -f 'player_recorder'; pkill -f 'ip_recorder|ip_tape'; pkill -f 'bookie_paper.py'; pkill -f 'bookie_xx.py'; pkill -f 'sports_team.py'; pkill -f 'integrity.py'
sleep 2; nohup /root/pe-sports/team/run_team.sh >/dev/null 2>&1 & disown; echo "reverted to Railway at $(date -u +%H:%M:%S)"
SH
chmod +x $MIG/cut_local.sh $MIG/cut_back.sh
echo "-- final delta of the three tapes right before the cut --"; timeout 1800 python3 - <<'PY'
import subprocess,sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds
# run the sync only for the tapes: skip-list = everything else
import psycopg2; R=psycopg2.connect(creds.pg_railway(),sslmode='require'); c=R.cursor(); c.execute("SELECT tablename FROM pg_tables WHERE schemaname='public'"); skip=[t for (t,) in c.fetchall() if t not in ('liq_sample','stream_ticks','ip_tape','xx_tape')]
subprocess.run(['python3','/root/pe-migrate/sync_railway.py',','.join(skip)])
PY
$MIG/cut_local.sh
echo "waiting 6 min for keepalives to relaunch the recorders..."; sleep 360
echo "== 5. proof =="
python3 - <<'PY' > $MIG/proof_536.txt; cat $MIG/proof_536.txt
import sys, psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
L=psycopg2.connect(creds.pg_local()); lc=L.cursor(); lc.execute("SET statement_timeout='60s'"); ok={}
for t,col in [('liq_sample','ts'),('stream_ticks','ts_recv'),('xx_tape','ts'),('ip_tape','ts'),('bookie_paper','ts'),('liq_heartbeat','last_seen')]:
    try: lc.execute(f'SELECT count(*), max("{col}") FROM "{t}" WHERE "{col}">now()-interval \'6 minutes\''); n,m=lc.fetchone(); ok[t]=n; print(f"LOCAL {t:14s} last 6 min: rows {n} max {m}")
    except Exception as e: print(f"LOCAL {t}: {str(e)[:80]}"); L.rollback(); ok[t]=0
print("PROOF", "PASS" if (ok.get('liq_sample',0)>0 or ok.get('stream_ticks',0)>0) else "FAIL")
PY
if grep -q "PROOF FAIL" $MIG/proof_536.txt; then echo "no local tape within 6 min — REVERTING both switches"; $MIG/cut_back.sh; else echo "cutover held: recorders write local. Railway untouched; hourly sync still pulls what the Railway-hosted goal-signal service writes."; fi
pgrep -fa 'liq_recorder|stream_client|xx_recorder|bookie_paper|bookie_xx|sports_team' | cut -c1-80
echo "536 done"
