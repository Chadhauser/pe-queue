#!/bin/bash
# 630 (Tue 17 Nov 2026, 07:12). 628: the goal monitor fires (log: fired=1/2) but every goal_alerts INSERT fails with a duplicate key -
# the id sequence is behind after the table restore, and the restored tables' sequences are not "owned", so 622 did not see it.
# Fix: on the database the brain writes to (its env exports creds.pg_railway()) and on local, move EVERY nextval() sequence up to the
# max of its column (only ever up). Restart monitor_ht and read its boot test. Report: reports/fix_630.md
R=/root/pe-queue/reports/fix_630.md
{
echo "# 630 goal alerts — $(date -u '+%F %H:%M') UTC"; echo; echo '```'
python3 - <<'PY'
import sys, re; sys.path.insert(0,'/root/pe-queue/runner'); import creds, psycopg2
from psycopg2.extensions import parse_dsn
def host(d):
    try: x=parse_dsn(d); return f"{x.get('host')}:{x.get('port')}/{x.get('dbname')}"
    except Exception: return re.sub(r'//[^@]*@','//***@',d).split('?')[0]
dbs={'brain (pg_railway)':creds.pg_railway(),'local':creds.pg_local()}
print({k:host(v) for k,v in dbs.items()})
seen=set()
for name,dsn in dbs.items():
    if host(dsn) in seen: print(name,"same database as above - skipped"); continue
    seen.add(host(dsn))
    con=psycopg2.connect(dsn,**({'sslmode':'disable'} if name=='local' else {})); con.autocommit=True; c=con.cursor(); c.execute("SET statement_timeout='200s'")
    c.execute("SELECT max(sent_at), count(*) FROM goal_alerts"); print(name,"goal_alerts last/rows:",c.fetchone())
    c.execute("""SELECT table_name, column_name, column_default FROM information_schema.columns
                 WHERE table_schema='public' AND column_default LIKE 'nextval(%%'""")
    moved=0
    for t,col,dflt in c.fetchall():
        seq=re.search(r"nextval\('([^']+)'",dflt).group(1)
        try:
            c.execute(f'SELECT max("{col}") FROM "{t}"'); mx=c.fetchone()[0]
            if mx is None: continue
            c.execute(f"SELECT last_value FROM {seq}"); lv=c.fetchone()[0]
            if mx>lv: c.execute("SELECT setval(%s,%s)",(seq,mx)); moved+=1; print(f"  {name} {t}.{col}: {lv} -> {mx}")
        except Exception as e: print(f"  {name} {t}.{col}: skipped {str(e)[:60]}")
    print(name,"sequences moved:",moved)
PY
echo '```'
echo "## restart monitor_ht"
pkill -f 'brain/monitor_ht.py'; sleep 60
echo "processes: $(pgrep -f 'brain/monitor_ht.py' | wc -l)"
echo '```'; grep -E "BOOT TEST|UniqueViolation" /root/pe-brain/monitor_ht.log | tail -3; tail -3 /root/pe-brain/monitor_ht.log; echo '```'
} > "$R" 2>&1
cd /root/pe-queue && git add "$R" && git commit -qm "630: goal alerts sequences" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
echo "630 done"
