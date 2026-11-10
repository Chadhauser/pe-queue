#!/bin/bash
# 548 (Tue 10 Nov 2026, 13:00). Three fixes, each with proof in this output.
#  A. DISK: box at ~15 GB free, under the loaders' 20 GB pause line (Gate FAIL since 07:25; the Railway copy + archives filled it). Tape
#     rows older than 10 days in stream_ticks, ip_tape, liq_sample are COPIED to compressed files under /root/pe-archive/<table>/<day>.csv.zst
#     (zstd, ~10x smaller; readable back with zstdcat | psql COPY), verified row-for-row, then deleted and the tables vacuumed. Nothing is
#     lost: the replay reads the live window; older tape is a file. The fair-price map reads bf_hist_*, untouched.
#  B. LIQ RECORDER: still writing Railway (local copy lags an hour). Diagnose from the RUNNING process (its open sockets), then force: kill
#     every liq_recorder process, confirm none, relaunch via the keepalive, prove local rows within 3 minutes.
#  C. STREAM UNIVERSE: pre-off football on the stream tape was Match Odds only, so 546 could not replay one passed cell. The recorder now
#     subscribes pre-off football markets of EVERY market type in fair_price_passed (next 2 h), so the replay and the bot share one tape.
#  Also: 545/546/547/548 added to the Watchman's REPORT_JOBS so their outputs reach the hourly report.
set -o pipefail
export PYTHONDONTWRITEBYTECODE=1
echo "== A. disk =="; df -h / | tail -1
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
c=psycopg2.connect(creds.pg_local(),sslmode='disable').cursor()
c.execute("SELECT tablename, pg_total_relation_size(quote_ident(tablename))/1e9 FROM pg_tables WHERE schemaname='public' ORDER BY 2 DESC LIMIT 12")
print("largest tables (GB):"); [print(f"  {t:28s} {g:6.1f}") for t,g in c.fetchall()]
c.execute("SELECT pg_database_size(current_database())/1e9"); print("database GB:",round(c.fetchone()[0],1))
PY
which zstd >/dev/null || apt-get install -y -qq zstd >/dev/null 2>&1
mkdir -p /root/pe-archive && cat > /root/pe-archive/archive_tape.py <<'PY'
# archive_tape (548): move tape rows older than KEEP_DAYS into compressed daily files, verify counts, delete, vacuum. Re-runnable; daily cron.
import sys, os, subprocess, datetime, psycopg2
sys.path.insert(0,'/root/pe-queue/runner'); import creds
KEEP_DAYS=int(os.environ.get('KEEP_DAYS','10'))
T=[('stream_ticks','ts_recv'),('ip_tape','ts'),('liq_sample','ts')]
con=psycopg2.connect(creds.pg_local(),sslmode='disable'); con.autocommit=True; c=con.cursor(); c.execute("SET statement_timeout=0")
for t,col in T:
    c.execute(f'SELECT min("{col}")::date, (now()-interval \'{KEEP_DAYS} days\')::date FROM "{t}"'); lo,hi=c.fetchone()
    if lo is None or lo>=hi: print(f"{t}: nothing older than {KEEP_DAYS} days"); continue
    d=lo
    while d<hi:
        out=f"/root/pe-archive/{t}"; os.makedirs(out,exist_ok=True); f=f"{out}/{d}.csv.zst"
        c.execute(f'SELECT count(*) FROM "{t}" WHERE "{col}">=%s AND "{col}"<%s',(d,d+datetime.timedelta(days=1))); n=c.fetchone()[0]
        if n:
            z=subprocess.Popen(['zstd','-q','-T2','-f','-o',f],stdin=subprocess.PIPE)   # stream COPY -> zstd -> file
            d1=d+datetime.timedelta(days=1)
            c.copy_expert(f'''COPY (SELECT * FROM "{t}" WHERE "{col}">='{d}' AND "{col}"<'{d1}' ORDER BY "{col}") TO STDOUT WITH (FORMAT csv, HEADER)''',z.stdin); z.stdin.close(); z.wait()
            lines=int(subprocess.run(f"zstdcat '{f}' | wc -l",shell=True,capture_output=True,text=True).stdout.strip() or 0)-1
            if lines==n and z.returncode==0:
                c.execute(f'DELETE FROM "{t}" WHERE "{col}">=%s AND "{col}"<%s',(d,d+datetime.timedelta(days=1))); print(f"{t} {d}: {n} rows -> {f} ({os.path.getsize(f)/1e6:.0f} MB), deleted")
            else: print(f"{t} {d}: VERIFY FAILED file {lines} vs table {n} — rows kept"); os.remove(f)
        d+=datetime.timedelta(days=1)
    c.execute(f'VACUUM (ANALYZE) "{t}"'); print(f"{t}: vacuumed")
PY
python3 -m py_compile /root/pe-archive/archive_tape.py && KEEP_DAYS=10 timeout 7000 python3 /root/pe-archive/archive_tape.py
( crontab -l 2>/dev/null | grep -v 'archive_tape.py'; echo "35 3 * * * KEEP_DAYS=10 timeout 7000 /usr/bin/python3 /root/pe-archive/archive_tape.py >> /root/pe-archive/archive.log 2>&1" ) | crontab -
echo "-- after --"; df -h / | tail -1; du -sh /root/pe-archive
echo "== B. liq recorder =="
for pid in $(pgrep -f liq_recorder.py); do echo "pid $pid cmd: $(tr '\0' ' ' </proc/$pid/cmdline | cut -c1-100) started $(ps -o lstart= -p $pid)"; ss -tnp 2>/dev/null | grep "pid=$pid," | awk '{print "   socket ->",$5}' | sort -u; done
grep -n "DB=\|bot_core\|545" /root/pe-liq/liq_recorder.py | head -5
grep -n "python\|liq_recorder" /root/pe-liq/keepalive.sh 2>/dev/null | head -3
pkill -9 -f liq_recorder.py; sleep 2; echo "liq processes after kill: $(pgrep -f liq_recorder.py | wc -l)"
sleep 150
for pid in $(pgrep -f liq_recorder.py); do echo "relaunched pid $pid"; ss -tnp 2>/dev/null | grep "pid=$pid," | awk '{print "   socket ->",$5}' | sort -u; done
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
c=psycopg2.connect(creds.pg_local(),sslmode='disable').cursor(); c.execute("select count(*), max(ts) from liq_sample where ts>now()-interval '3 minutes'"); n,m=c.fetchone()
c.execute("select last_seen, live_markets from liq_heartbeat"); hb=c.fetchall()
print("LOCAL liq_sample last 3 min:",n,m,"| heartbeat",hb,"| PROOF","PASS" if n else ("no in-play football right now (heartbeat live_markets 0) — re-check at the next kick-off" if hb and hb[0][1]==0 else "FAIL"))
PY
echo "== C. stream pre-off universe = passed-cell market types =="
cd /root/pe-stream && cp stream_client.py stream_client.py.bak_548 && python3 - <<'PY'
p='/root/pe-stream/stream_client.py'; s=open(p).read()
if 'fair_price_passed' in s: print("already patched"); raise SystemExit
anchor="def refresh_universe(tok):"
assert s.count(anchor)==1
add='''def _passed_types():
    try:
        import psycopg2 as _pg, sys as _sy; _sy.path.insert(0,'/root/pe-queue/runner'); import creds as _cr
        c=_pg.connect(_cr.pg_local(),sslmode='disable').cursor(); c.execute("SELECT DISTINCT market_type FROM fair_price_passed WHERE sport='Soccer'"); return sorted({t for (t,) in c.fetchall()}|{'MATCH_ODDS'})
    except Exception as e: print("passed types read failed",repr(e)[:80],flush=True); return ['MATCH_ODDS']
def refresh_universe(tok):'''
s=s.replace(anchor,add,1)
# add the pre-off football block right after the function header's first line that builds `out`
i=s.index("def refresh_universe(tok):"); j=s.index("\n",i)+1
# find the 'return out' of refresh_universe and insert before it
k=s.index("    return out",i)
block='''    # 548: pre-off football of every passed-cell market type, next 2 hours — the tape the replay and the bot share
    try:
        t0=datetime.datetime.utcnow(); f={"eventTypeIds":["1"],"marketTypeCodes":_passed_types(),"marketStartTime":{"from":t0.strftime('%Y-%m-%dT%H:%M:%SZ'),"to":(t0+datetime.timedelta(hours=2)).strftime('%Y-%m-%dT%H:%M:%SZ')}}
        for m in api(tok,'listMarketCatalogue',{"filter":f,"marketProjection":["EVENT","RUNNER_DESCRIPTION","MARKET_START_TIME","MARKET_DESCRIPTION"],"maxResults":200}):
            if m['marketId'] in out: continue
            out[m['marketId']]=dict(sport='football',mkt=(m.get('description') or {}).get('marketType','MO_PRE'),ev=m['event']['name'],start=datetime.datetime.fromisoformat(m['marketStartTime'].replace('Z','+00:00')),names={r['selectionId']:r['runnerName'] for r in m['runners']})
    except Exception as e: print("pre-off universe",repr(e)[:100],flush=True)
'''
s=s[:k]+block+s[k:]; open(p,'w').write(s); print("stream universe: pre-off football = passed-cell types")
PY
python3 -m py_compile stream_client.py && echo "stream compiles" || { cp stream_client.py.bak_548 stream_client.py; echo RESTORED; }
pkill -f stream_client.py; sleep 90; python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require').cursor(); c.execute("SELECT mkt, count(*) FROM stream_ticks WHERE ts_recv>now()-interval '2 minutes' AND sport='football' GROUP BY 1 ORDER BY 2 DESC"); print("football ticks by market type, last 2 min:",c.fetchall())
PY
for j in 545 546 547 548; do grep -q "^$j$" /root/pe-queue/watchman/REPORT_JOBS.txt || echo $j >> /root/pe-queue/watchman/REPORT_JOBS.txt; done
cd /root/pe-queue && git add watchman/REPORT_JOBS.txt && git commit -q -m "548: report jobs" && git pull -q --rebase && git push -q || true
echo "548 done"
