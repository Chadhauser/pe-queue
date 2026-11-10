#!/bin/bash
# 357 (5 Nov 2026) THE GATE: /root/pe-data/integrity_suite.py runs daily at 07:00 and writes integrity_suite on the local DB.
# 411 (watchman fix of integrity_suite.py, 10 Nov): the 06:05 UTC run wrote nothing. Its duplicate check (line 28, a full GROUP BY on
#   bf_hist_other) ran past the 4-minute read killer, which ended the local connection ("terminating connection due to administrator
#   command", postgres log 07:05:01 CET). q() hid every later error, then line 47 crashed with "cursor already closed".
#   Fix: a 200 s statement_timeout on the local cursor (so the slow check is cancelled and comes back -1, the connection lives), and a
#   reconnect before the INSERT. No check is changed. Then the suite runs once so today's gate has a row.
set -o pipefail
P=/root/pe-data/integrity_suite.py
[ -f $P.bak_411 ] || cp $P $P.bak_411
python3 - <<'PY'
p='/root/pe-data/integrity_suite.py'; s=open(p).read()
a_old="L=psycopg2.connect(creds.pg_local()); L.autocommit=True; lc=L.cursor()\n"
a_new="L=psycopg2.connect(creds.pg_local()); L.autocommit=True; lc=L.cursor(); lc.execute(\"SET statement_timeout='200s'\")\n"
b_old="now=datetime.datetime.now(datetime.timezone.utc)\nfor n,s,v,d in out: lc.execute("
b_new="now=datetime.datetime.now(datetime.timezone.utc)\nif L.closed or lc.closed: L=psycopg2.connect(creds.pg_local()); L.autocommit=True; lc=L.cursor()\nfor n,s,v,d in out: lc.execute("
if "statement_timeout='200s'" in s: print("already patched")
elif s.count(a_old)==1 and s.count(b_old)==1:
    s=s.replace(a_old,a_new).replace(b_old,b_new); open(p,'w').write(s); print("suite patched")
else: print("SUITE ANCHOR NOT FOUND - unchanged"); raise SystemExit(1)
PY
[ $? -eq 0 ] || exit 1
python3 -m py_compile $P || { cp $P.bak_411 $P; echo "compile failed, restored"; exit 1; }
echo "== suite run"
timeout 1500 python3 $P 2>&1 | grep -v Deprecation | tail -34
echo "411 done"
