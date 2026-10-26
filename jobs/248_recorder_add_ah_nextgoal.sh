#!/bin/bash
# 248: markets we never look at, step 1 — add ASIAN_HANDICAP ('AH') and NEXT_GOAL ('NG') to the in-play liquidity recorder so the
# opportunity map and the sweeps can see them (the two-season history only holds MO/OU/FH/BTTS, so these start accruing today).
# Selection names for the new markets are kept raw (upper-cased). Restart + heartbeat + first rows check.
set -e
python3 - <<'PY'
import re
p='/root/pe-liq/liq_recorder.py'; s=open(p).read(); orig=s
m=re.search(r"for mt in \(([^)]*)\):",s); assert m, "mt loop not found"
if "'ASIAN_HANDICAP'" not in m.group(1):
    s=s.replace(m.group(0),f"for mt in ({m.group(1).rstrip(',')},'ASIAN_HANDICAP','NEXT_GOAL'):",1); print("market types added")
s=s.replace("'BOTH_TEAMS_TO_SCORE':'BTTS'}","'BOTH_TEAMS_TO_SCORE':'BTTS','ASIAN_HANDICAP':'AH','NEXT_GOAL':'NG'}") if "'ASIAN_HANDICAP':'AH'" not in s else s
anchor="    if meta['mkt']=='CS': return low.replace(' ','').upper()"
if anchor in s and "meta['mkt'] in ('AH','NG')" not in s:
    s=s.replace(anchor,"    if meta['mkt'] in ('AH','NG'): return low.upper()[:40]\n"+anchor,1); print("selname branch added")
assert s!=orig; open(p,'w').write(s)
print([l.strip()[:150] for l in s.splitlines() if 'for mt in' in l or "'AH'" in l][:4])
PY
python3 -m py_compile /root/pe-liq/liq_recorder.py; pkill -f liq_recorder.py || true; sleep 3; ls /root/pe-liq/keepalive*.sh && /root/pe-liq/keepalive.sh || true
sleep 120; pgrep -af liq_recorder.py | head -1; tail -3 /root/pe-liq/*.log | tail -5
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
k=psycopg2.connect(DB,sslmode='require').cursor()
k.execute("SELECT mkt, count(*), count(DISTINCT market_id) FROM liq_sample WHERE ts>now()-interval '3 minutes' GROUP BY mkt ORDER BY 1"); print("rows last 3 min by market:",k.fetchall())
k.execute("SELECT event_name, mkt, sel, back_px, lay_px FROM liq_sample WHERE mkt IN ('AH','NG') ORDER BY ts DESC LIMIT 6"); [print("  ",r) for r in k.fetchall()]
PY
