#!/bin/bash
# 535 (Sun 8 Nov 2026). RAILWAY -> CONTABO, step 1 of 2. Peter: "should have been done already" — agreed, planned Fri-Sun, not started.
# What this does: (1) copies every table in the Railway database into the local PostgreSQL (db petrade): tables we do not hold yet are
# dumped whole (schema + data); tables we already hold (the archived tapes liq_sample / ip_tape / stream_ticks and anything else) get
# only the rows newer than our local maximum on their time column; (2) makes creds.pg_railway() return the LOCAL DSN so every recorder,
# bot, daemon and job moves in one place, keeping the old DSN as creds.pg_railway_remote(); (3) restarts the writers (keepalive crons
# relaunch them) and proves they write locally; (4) installs an hourly pull of the tables the Railway-hosted goal-signal service still
# writes (goal_alerts, m1_alerts, real_trades, ...) until that service moves on Monday (step 2). Railway is NOT touched: nothing dropped,
# nothing deleted; /root/pe-queue/runner/creds_revert_535.sh puts the old DSN back in one command if anything is wrong.
set -o pipefail
export PYTHONDONTWRITEBYTECODE=1
echo "== 0. pre-flight =="; df -h / | tail -1; psql --version; pg_dump --version
cd /root/pe-queue/runner && test -f creds.py && cp creds.py creds.py.bak_535 && python3 -c "
import sys; sys.path.insert(0,'.'); import creds; print('railway dsn host:', [p for p in creds.pg_railway().replace('@',' ').replace('/',' ').split() if 'rlwy' in p or 'railway' in p][:1]); print('local dsn ok:', bool(creds.pg_local()))"
if grep -q 'pg_railway_remote' creds.py; then echo "creds already switched (pg_railway_remote present) — skipping copy preamble? no: copy runs anyway from the remote DSN"; fi
mkdir -p /root/pe-migrate && cat > /root/pe-migrate/copy_railway.py <<'PY'
import sys, io, os, time, datetime, subprocess, psycopg2, psycopg2.extras
sys.path.insert(0,'/root/pe-queue/runner'); import creds
REMOTE=getattr(creds,'pg_railway_remote',creds.pg_railway)(); LOCAL=creds.pg_local()
R=psycopg2.connect(REMOTE,sslmode='require',connect_timeout=20); R.autocommit=True; rc=R.cursor(); rc.execute("SET statement_timeout=0")
L=psycopg2.connect(LOCAL,sslmode='prefer'); L.autocommit=True; lc=L.cursor(); lc.execute("SET statement_timeout=0")
rc.execute("SELECT tablename, pg_total_relation_size(quote_ident(tablename)) FROM pg_tables WHERE schemaname='public' ORDER BY 2 DESC"); tabs=rc.fetchall()
lc.execute("SELECT tablename FROM pg_tables WHERE schemaname='public'"); have={t for (t,) in lc.fetchall()}
TS_COLS=('ts','ts_recv','sent_at','created_at','placed_at','started','run_at','logged_at','seen_at','at','t','when_ts')
log=open('/root/pe-migrate/copy_535.log','a'); T0=time.time(); summary=[]
def cols(cur,t): cur.execute("SELECT column_name, data_type FROM information_schema.columns WHERE table_schema='public' AND table_name=%s ORDER BY ordinal_position",(t,)); return cur.fetchall()
for t,size in tabs:
    t0=time.time(); note=''
    try:
        if t not in have:
            # whole table: schema + data, via pg_dump | psql (no owner/privileges)
            p1=subprocess.Popen(['pg_dump','--no-owner','--no-privileges','--no-comments','-t',f'public.{t}',REMOTE],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
            p2=subprocess.run(['psql','-v','ON_ERROR_STOP=0','-q',LOCAL],stdin=p1.stdout,capture_output=True,text=True); p1.stdout.close(); err=p1.stderr.read().decode()[-200:]
            lc.execute(f'SELECT count(*) FROM "{t}"'); n=lc.fetchone()[0]; note=f"NEW whole copy rows {n}"+(f" dump-err {err!r}" if err.strip() else '')
        else:
            rcols=cols(rc,t); lcols=cols(lc,t); rn=[c for c,_ in rcols]; ln={c for c,_ in lcols}; common=[c for c in rn if c in ln]
            tscol=next((c for c in TS_COLS if c in common),None)
            if not common: note='SKIP no common columns'
            elif tscol:
                lc.execute(f'SELECT max("{tscol}") FROM "{t}"'); mx=lc.fetchone()[0]
                where=f'WHERE "{tscol}" > %s' if mx is not None else ''
                collist=','.join(f'"{c}"' for c in common)
                sql=rc.mogrify(f'COPY (SELECT {collist} FROM "{t}" {where}) TO STDOUT',(mx,) if mx is not None else None).decode()
                tmp=f'/root/pe-migrate/.delta_{t}.tsv'
                with open(tmp,'w') as f: rc.copy_expert(sql,f)
                n=sum(1 for _ in open(tmp))
                with open(tmp) as f: lc.copy_expert(f'COPY "{t}" ({collist}) FROM STDIN',f)
                os.remove(tmp); note=f"DELTA since {str(mx)[:19]} rows {n}"
            else:
                # no time column and table exists locally: bring rows across with conflict-ignore when a primary key exists
                rc.execute("SELECT a.attname FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid=%s::regclass AND i.indisprimary",(f'public."{t}"',)); pk=[c for (c,) in rc.fetchall()]
                collist=','.join(f'"{c}"' for c in common)
                buf=io.StringIO(); rc.copy_expert(f'COPY (SELECT {collist} FROM "{t}") TO STDOUT',buf); buf.seek(0); n=buf.getvalue().count('\n'); buf.seek(0)
                if pk and all(c in common for c in pk):
                    lc.execute(f'CREATE TEMP TABLE _m535 AS SELECT {collist} FROM "{t}" WITH NO DATA'); lc.copy_expert(f'COPY _m535 ({collist}) FROM STDIN',buf)
                    lc.execute(f'INSERT INTO "{t}" ({collist}) SELECT {collist} FROM _m535 ON CONFLICT DO NOTHING'); ins=lc.rowcount; lc.execute('DROP TABLE _m535'); note=f"MERGE by pk rows remote {n} inserted {ins}"
                else:
                    lc.execute(f'SELECT count(*) FROM "{t}"'); ln_=lc.fetchone()[0]
                    if ln_==0: lc.copy_expert(f'COPY "{t}" ({collist}) FROM STDIN',buf); note=f"FILL empty local rows {n}"
                    else: note=f"LEFT local has {ln_} rows, remote {n}, no pk/time column — local kept (same-named local table)"
    except Exception as e:
        note=f"ERROR {str(e)[:160]!r}"
        try: L.rollback()
        except Exception: pass
    line=f"{t:40s} {size/1e6:9.1f} MB  {time.time()-t0:6.0f}s  {note}"; print(line,flush=True); log.write(datetime.datetime.utcnow().isoformat()+' '+line+'\n'); summary.append((t,note))
print(f"copied {len(tabs)} tables in {(time.time()-T0)/60:.1f} min; errors {sum(1 for _,n in summary if n.startswith('ERROR'))}")
PY
python3 -m py_compile /root/pe-migrate/copy_railway.py && echo "copier compiles"
echo "== 0b. local SSL (writers connect with sslmode=require) =="
python3 - <<'PY2'
import sys, psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
try: psycopg2.connect(creds.pg_local(),sslmode='require',connect_timeout=10).close(); print("local accepts sslmode=require: OK")
except Exception as e:
    print("local refuses sslmode=require:",str(e)[:120]); open('/root/pe-migrate/.need_ssl','w').write('1')
PY2
if [ -f /root/pe-migrate/.need_ssl ]; then
  CONF=$(psql -At -c "show config_file" "$(python3 -c "import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds; print(creds.pg_local())")" 2>/dev/null)
  echo "enabling ssl in $CONF with the system snakeoil certificate"
  ls /etc/ssl/certs/ssl-cert-snakeoil.pem /etc/ssl/private/ssl-cert-snakeoil.key >/dev/null 2>&1 || make-ssl-cert generate-default-snakeoil --force-overwrite
  usermod -a -G ssl-cert postgres 2>/dev/null
  grep -q '^ssl = on' "$CONF" || printf "\nssl = on\nssl_cert_file = '/etc/ssl/certs/ssl-cert-snakeoil.pem'\nssl_key_file = '/etc/ssl/private/ssl-cert-snakeoil.key'\n" >> "$CONF"
  systemctl restart postgresql || pg_ctlcluster 18 main restart
  sleep 5; rm -f /root/pe-migrate/.need_ssl
  python3 -c "import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds; psycopg2.connect(creds.pg_local(),sslmode='require').close(); print('ssl now OK')" || { echo "SSL still refused — STOP before switching creds"; exit 1; }
fi
echo "== 1. copy Railway -> local (whole for new tables, delta for held ones) =="
timeout 10800 python3 /root/pe-migrate/copy_railway.py
echo "== 2. switch creds: pg_railway() -> local, old DSN kept as pg_railway_remote() =="
cd /root/pe-queue/runner
if ! grep -q 'pg_railway_remote' creds.py; then
cat >> creds.py <<'PY'

# 535 (8 Nov 2026): the trading database now lives on this box. Every caller of pg_railway() gets the local DSN; the Railway DSN stays
# reachable as pg_railway_remote() for the hourly pull of the tables the Railway-hosted goal-signal service still writes (until step 2).
pg_railway_remote = pg_railway
def pg_railway(): return pg_local()
PY
fi
python3 -c "import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds; assert creds.pg_railway()==creds.pg_local(); assert creds.pg_railway_remote()!=creds.pg_local(); print('creds switched: pg_railway() is local, remote kept')"
cat > /root/pe-queue/runner/creds_revert_535.sh <<'SH'
#!/bin/bash
# one-command revert: Railway DSN back for everything
cp /root/pe-queue/runner/creds.py.bak_535 /root/pe-queue/runner/creds.py && pkill -f 'liq_recorder.py|stream_client|xx_recorder|bookie_paper.py|bookie_xx.py|sports_team.py|player_recorder|goal_signal|coach' ; echo reverted
SH
chmod +x /root/pe-queue/runner/creds_revert_535.sh
echo "== 3. hourly pull of Railway-written tables until the goal-signal service moves (step 2, Monday) =="
cat > /root/pe-migrate/pull_remote.py <<'PY'
import sys, io, psycopg2
sys.path.insert(0,'/root/pe-queue/runner'); import creds
TABLES=[('goal_alerts','sent_at'),('m1_alerts','ts'),('real_trades','placed_at'),('job_results','started'),('watchdog_log','ts'),('integrity_log','ts'),('coach_tape','tape_date')]
R=psycopg2.connect(creds.pg_railway_remote(),sslmode='require',connect_timeout=20); rc=R.cursor(); rc.execute("SET statement_timeout='120s'")
L=psycopg2.connect(creds.pg_local()); L.autocommit=True; lc=L.cursor()
for t,col in TABLES:
    try:
        lc.execute(f'SELECT max("{col}") FROM "{t}"'); mx=lc.fetchone()[0]
        rc.execute("SELECT column_name FROM information_schema.columns WHERE table_name=%s ORDER BY ordinal_position",(t,)); rcols=[c for (c,) in rc.fetchall()]
        lc.execute("SELECT column_name FROM information_schema.columns WHERE table_name=%s",(t,)); lcols={c for (c,) in lc.fetchall()}
        common=','.join(f'"{c}"' for c in rcols if c in lcols)
        sql=rc.mogrify(f'COPY (SELECT {common} FROM "{t}" WHERE "{col}" > %s) TO STDOUT',(mx,)).decode() if mx is not None else f'COPY (SELECT {common} FROM "{t}") TO STDOUT'
        buf=io.StringIO(); rc.copy_expert(sql,buf); n=buf.getvalue().count('\n'); buf.seek(0); lc.copy_expert(f'COPY "{t}" ({common}) FROM STDIN',buf); print(t,'pulled',n)
    except Exception as e: print(t,'ERR',str(e)[:120]); L.rollback() if not L.autocommit else None
PY
python3 -m py_compile /root/pe-migrate/pull_remote.py && ( crontab -l 2>/dev/null | grep -v 'pe-migrate/pull_remote.py'; echo "7 * * * * timeout 600 /usr/bin/python3 /root/pe-migrate/pull_remote.py >> /root/pe-migrate/pull_remote.log 2>&1" ) | crontab - && echo "hourly pull installed (:07)"
echo "== 4. restart writers so they open the local database (keepalive crons relaunch them) =="
pkill -f 'liq_recorder.py'; pkill -f 'stream_client'; pkill -f 'xx_recorder'; pkill -f 'player_recorder'; pkill -f 'bookie_paper.py'; pkill -f 'bookie_xx.py'; pkill -f 'sports_team.py'; sleep 2
nohup /root/pe-sports/team/run_team.sh >/dev/null 2>&1 & disown
echo "waiting 5 min for the recorders to come back and write..."; sleep 300
echo "== 5. proof: rows written LOCALLY in the last 5 minutes, and row counts both sides =="
python3 - <<'PY'
import sys, psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
L=psycopg2.connect(creds.pg_local()); lc=L.cursor(); lc.execute("SET statement_timeout='60s'")
R=psycopg2.connect(creds.pg_railway_remote(),sslmode='require',connect_timeout=20); rc=R.cursor(); rc.execute("SET statement_timeout='60s'")
for t,col in [('liq_sample','ts'),('stream_ticks','ts_recv'),('xx_tape','ts'),('ip_tape','ts'),('bookie_paper','ts')]:
    try: lc.execute(f'SELECT count(*), max("{col}") FROM "{t}" WHERE "{col}">now()-interval \'5 minutes\''); print(f"LOCAL {t:14s} last 5 min:",lc.fetchone())
    except Exception as e: print(f"LOCAL {t}: {str(e)[:80]}"); L.rollback()
for t in ['goal_alerts','m1_alerts','liq_goal_depth','job_results','xx_tape','liq_sample','stream_ticks']:
    a=b=None
    try: lc.execute(f'SELECT count(*) FROM "{t}"'); a=lc.fetchone()[0]
    except Exception as e: L.rollback(); a=str(e)[:40]
    try: rc.execute(f'SELECT count(*) FROM "{t}"'); b=rc.fetchone()[0]
    except Exception as e: R.rollback(); b=str(e)[:40]
    print(f"COUNT {t:14s} local {a} | railway {b}")
PY
pgrep -fa 'liq_recorder|stream_client|xx_recorder|bookie_paper|bookie_xx|sports_team' | cut -c1-90
echo "535 done. Railway untouched (fallback: /root/pe-queue/runner/creds_revert_535.sh). Step 2 Monday: goal-signal service onto this box, then cancel Railway."
