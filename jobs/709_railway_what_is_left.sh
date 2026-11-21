#!/bin/bash
# 709 (Sat 21 Nov 2026 16:14, Peter: Railway should not be used; do not ask him for screenshots). Read-only: find out from the
# server itself what is still running on Railway and what still depends on it, so it can be shut without asking Peter to look.
# No credentials printed. Nothing stopped, nothing deleted in this job.
R=/root/pe-queue/reports/railway_709.md
{
echo "# What is still on Railway - $(date -u '+%F %H:%M') UTC"; echo
echo "## Can this server control Railway itself?"
echo "- railway command installed: $(command -v railway >/dev/null && echo yes || echo no)"
echo "- a Railway login or token on this server: $( { ls /root/.railway/config.json >/dev/null 2>&1 && echo 'login file present'; } ; grep -rlsE 'RAILWAY_(API_)?TOKEN' /root/.bashrc /root/.profile /root/operators/.env /root/pe-queue-state 2>/dev/null | sed 's/.*/token variable present in &/' ; true)"
if command -v railway >/dev/null; then echo; echo '```'; timeout 30 railway whoami 2>&1 | sed -E 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+/<email>/g' | head -3; timeout 30 railway list 2>&1 | head -20; timeout 30 railway status 2>&1 | head -20; echo '```'; fi
echo; echo "## What on THIS server still talks to the Railway database (host names only)"
python3 - <<'PY'
import sys,re,subprocess
sys.path.insert(0,'/root/pe-queue/runner')
try:
    import creds
    names=[n for n in dir(creds) if n.startswith('pg')]
    for n in names:
        try:
            v=getattr(creds,n)(); h=re.search(r'@([^:/]+)',v if isinstance(v,str) else str(v)); print(f"- creds.{n}() points at host: {h.group(1) if h else 'unknown'}")
        except Exception as e: print(f"- creds.{n}(): {type(e).__name__}")
except Exception as e: print("- creds unreadable:",type(e).__name__)
out=subprocess.run("grep -rlsE 'railway\\.app|rlwy\\.net|proxy\\.rlwy' /root --include=*.py --include=*.sh --include=*.env --include=*.json --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=pe-archive 2>/dev/null | head -60",shell=True,capture_output=True,text=True).stdout.strip().splitlines()
print(f"- files on this server that name a Railway address: {len(out)}")
for f in out[:40]: print("  -",f)
PY
echo; echo "## Is the old Railway database still being written, and by what"
python3 - <<'PY'
import sys,re
sys.path.insert(0,'/root/pe-queue/runner')
try:
    import creds, psycopg2
    cands=[n for n in dir(creds) if 'rail' in n.lower() and ('old' in n.lower() or 'remote' in n.lower() or 'orig' in n.lower())]
    print("- ways to reach the OLD Railway database from creds:", cands or "none named (pg_railway now points at this server)")
    for n in cands:
        try:
            c=psycopg2.connect(getattr(creds,n)(),connect_timeout=15); k=c.cursor()
            k.execute("select relname, n_tup_ins from pg_stat_user_tables order by n_tup_ins desc limit 15"); print("  busiest tables (rows ever inserted):", k.fetchall())
            k.execute("select application_name, client_addr is not null, state, count(*) from pg_stat_activity where datname=current_database() group by 1,2,3 order by 4 desc limit 15"); print("  connected right now (program, remote?, state, count):", k.fetchall())
            k.execute("select pg_size_pretty(pg_database_size(current_database()))"); print("  size:", k.fetchone()[0])
        except Exception as e: print("  ",n,"->",type(e).__name__, str(e)[:120])
except Exception as e: print("- could not check:",type(e).__name__)
PY
echo; echo "## Earlier findings on record"; ls /root/pe-queue/reports | grep -i railway | sed 's/^/- /'
} > $R 2>&1
cd /root/pe-queue && git add "$R" && git commit -qm "709: what is still on Railway (read-only)" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
