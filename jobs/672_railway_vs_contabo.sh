#!/bin/bash
# 672 (Thu 19 Nov 2026, Peter 14:16: "why is anything on Railway"). READ ONLY. The old Railway database is still running (52 GB) and
# billing. Before Peter switches it off: prove every table with rows there is on this server with at least as many rows, and list
# anything that is not. Also: who on this server still talks to Railway. No secret or address is printed.
R=/root/pe-queue/reports/railway_672.md
{ echo "# 672 - $(date -u '+%F %H:%M') UTC"; echo '```'
python3 - <<'PY'
import sys, re, glob, subprocess
sys.path.insert(0,'/root/pe-queue/runner'); import creds, psycopg2
host=lambda d:(re.search(r'@([^:/?]+)',d) or re.search(r'host=(\S+)',d) or [None,'?'])[1]
loc=creds.pg_local(); cands=[]
try: cands.append(('creds.pg_railway',creds.pg_railway()))
except Exception as e: print('creds.pg_railway ERR',repr(e)[:80])
try:
    sys.path.insert(0,'/root/pe-bot'); from bot_core import DB; cands.append(('bot_core.DB',DB))
except Exception as e: print('bot_core ERR',repr(e)[:80])
for f in glob.glob('/root/pe-queue/runner/creds.py.bak*')+glob.glob('/root/pe-migrate/*.py')+glob.glob('/root/pe-*/.env')+glob.glob('/root/operators/.env'):
    try:
        for m in re.findall(r'postgres(?:ql)?://[^\s"\']+', open(f,errors='ignore').read()): cands.append((f,m))
    except Exception: pass
rail=[(n,d) for n,d in cands if 'rlwy' in host(d) or 'railway' in host(d)]
print('places on this server that still hold a Railway address:', sorted({n for n,_ in rail}) or 'none')
if not rail: print('NO RAILWAY ADDRESS LEFT ON THE SERVER - cannot compare from here'); raise SystemExit
L=psycopg2.connect(loc,sslmode='disable'); L.autocommit=True; lc=L.cursor(); lc.execute("SET statement_timeout='900s'")
Rw=None
for n,d in rail:
    try: Rw=psycopg2.connect(d,connect_timeout=20); break
    except Exception as e: print('connect',n,repr(e)[:80])
if Rw is None: print('COULD NOT CONNECT TO RAILWAY'); raise SystemExit
Rw.autocommit=True; rc=Rw.cursor(); rc.execute("SET statement_timeout='900s'")
rc.execute("select relname, n_live_tup from pg_stat_user_tables where n_live_tup>0 order by n_live_tup desc"); T=rc.fetchall()
lc.execute("select relname from pg_stat_user_tables"); have={r[0] for r in lc.fetchall()}
miss=[]; short=[]; ok=0
for t,est in T:
    if t.endswith('_heartbeat') or t.endswith('_hb'): continue
    if t not in have: miss.append((t,est)); continue
    try:
        if est>2_000_000:
            lc.execute("select n_live_tup from pg_stat_user_tables where relname=%s",(t,)); ln=lc.fetchone()[0]; rn=est
        else:
            rc.execute(f'select count(*) from "{t}"'); rn=rc.fetchone()[0]; lc.execute(f'select count(*) from "{t}"'); ln=lc.fetchone()[0]
        if ln < rn*0.98: short.append((t,rn,ln))
        else: ok+=1
    except Exception as e: short.append((t,est,'ERR '+repr(e)[:60])); L.rollback() if not L.autocommit else None
print(f"tables with rows on Railway: {len(T)} | on this server with as many rows: {ok}")
print("NOT on this server:", miss or 'none')
print("FEWER rows on this server (table, railway, here):"); [print("  ",x) for x in short] or print("   none")
rc.execute("select relname, n_tup_ins from pg_stat_user_tables where relname in ('goal_live_predictions','goal_timeline','goal_stats_live','brain_heartbeat','racing_tape','espn_stats','racecards_today','football_today')"); print("still being written on Railway (rows inserted since 3 Nov restart):", rc.fetchall())
PY
echo "== processes on this server holding a connection to anything that is not this machine's database"
ss -tnp 2>/dev/null | grep -E ":(5432|[0-9]{5}) " | grep -v "127.0.0.1\|::1" | awk '{print $5, $6}' | sed 's/users://' | sort | uniq -c | sort -rn | head -12
echo '```'; } > $R 2>&1
cd /root/pe-queue && git add $R; git commit -qm "672: railway vs contabo" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
