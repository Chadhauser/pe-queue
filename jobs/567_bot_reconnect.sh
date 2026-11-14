#!/bin/bash
# 567 (Sat 14 Nov 2026, 07:30). The bot crashed every 50 s from Thu 23:58 to Sat 05:48 with "cursor already closed" — a dropped
# database connection it never re-opened; the keepalive restarted it into the same dead connection path. Fix the mechanism, not the
# symptom: a reconnecting cursor. Minimal patch — the module-level local connection/cursor get a helper that reconnects on
# InterfaceError/OperationalError and retries once; the cells() read and the order insert go through it. Nothing else changes.
set -o pipefail
P=/root/pe-sports/bookie/bookie_v2.py; cp $P $P.bak_567
python3 - <<'PY'
import re
p='/root/pe-sports/bookie/bookie_v2.py'; s=open(p).read()
assert '567' not in s
# find how the local connection is made
m=re.search(r'^(\w+)\s*=\s*psycopg2\.connect\((.*?)\)\s*;?\s*(.*)$', s, re.M)
print("connect line:", m.group(0)[:160] if m else None)
lines=[l for l in s.split('\n') if 'psycopg2.connect' in l]; print("connect lines:", len(lines)); [print("  ",l[:150]) for l in lines]
cur=[l for l in s.split('\n') if re.search(r'\blc\s*=', l)]; print("lc lines:", [l.strip()[:120] for l in cur])
PY
echo "-- patch --"
python3 - <<'PY'
import re
p='/root/pe-sports/bookie/bookie_v2.py'; s=open(p).read()
m=re.search(r'^(\s*)lc\s*=\s*(\w+)\.cursor\(\)\s*$', s, re.M)
assert m, "lc is not a plain <conn>.cursor() — not patching blind"
indent, con = m.group(1), m.group(2)
cm=re.search(r'^\s*'+con+r'\s*=\s*(psycopg2\.connect\(.*\))\s*$', s, re.M)
assert cm, f"no plain connect line for {con}"
connect_expr=cm.group(1)
settings=[l.strip() for l in s.split('\n') if re.match(r'^\s*'+con+r'\.(autocommit|set_session|set_isolation_level)', l)]
body=f"""{indent}lc = {con}.cursor()
{indent}# 567: reconnecting cursor — a dropped connection is re-opened (same settings) and the statement retried once
{indent}def _reopen():
{indent}    global {con}
{indent}    {con} = {connect_expr}
""" + "".join(f"{indent}    {ln}\n" for ln in settings) + f"""{indent}    return {con}.cursor()
{indent}class _ReCur:
{indent}    def __init__(self): self._c = {con}.cursor()
{indent}    def execute(self, *a, **k):
{indent}        try: return self._c.execute(*a, **k)
{indent}        except (psycopg2.InterfaceError, psycopg2.OperationalError) as e:
{indent}            log(f"db connection lost ({{str(e)[:60]}}) — reconnecting"); self._c = _reopen(); return self._c.execute(*a, **k)
{indent}    def __getattr__(self, n): return getattr(self._c, n)
{indent}lc = _ReCur()"""
s=s.replace(m.group(0), body, 1); open(p,'w').write(s); print("patched; connection", con, "settings carried:", settings)
PY
python3 -m py_compile $P && echo compiles || { cp $P.bak_567 $P; echo "RESTORED (patch did not compile)"; exit 1; }
pkill -f "python3 bookie_v2.py"; sleep 50; pgrep -fa "bookie_v2.py" | cut -c1-80; tail -6 /root/pe-sports/bookie/bookie_v2.log | cut -c1-200
echo "567 done"
