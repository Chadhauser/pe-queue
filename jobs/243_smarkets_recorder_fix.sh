#!/bin/bash
# 243: Smarkets recorder root cause (241): the markets endpoint rejects the `limit` query parameter (HTTP 400 "Unknown query string
# properties: limit") on every call, the per-chunk error was swallowed, and the heartbeat still wrote 'ok' — zero rows for 12 days.
# Fix: drop `limit` from the markets and contracts calls, keep only match events (type contains 'match', not outrights), and make the
# heartbeat honest: note='ok' only when rows were written, otherwise 'no rows: <last error>'. Restart and verify rows within 90 s.
set -e
python3 - <<'PY'
import re
p='/root/pe-xx/xx_recorder.py'; s=open(p).read(); n=0
s2=re.sub(r'sm\((f"events/\{[^"]*\}/markets/"),\s*\{"limit":\s*\d+\}\)',r'sm(\1)',s); n+=int(s2!=s); s=s2
s2=re.sub(r'sm\((f"markets/\{[^"]*\}/contracts/"),\s*\{"limit":\s*\d+\}\)',r'sm(\1)',s); n+=int(s2!=s); s=s2
old='        ev=sm("events/",{"state":"live","type_domain":sport,"limit":200}).get(\'events\',[])\n'
if old in s: s=s.replace(old,old+"        ev=[e for e in ev if 'match' in str(e.get('type','')).lower()]\n",1); n+=1
old2='''            if rows: psycopg2.extras.execute_values(cur,"INSERT INTO xx_tape VALUES %s",rows)
            cur.execute("INSERT INTO xx_heartbeat VALUES (%s,NOW(),%s,'ok') ON CONFLICT (exchange) DO UPDATE SET last_seen=NOW(), live_markets=EXCLUDED.live_markets, note='ok'",(name,live))'''
new2='''            if rows: psycopg2.extras.execute_values(cur,"INSERT INTO xx_tape VALUES %s",rows)
            note='ok' if rows else ('no rows: '+LAST_ERR.get(name,'none')[:150])
            cur.execute("INSERT INTO xx_heartbeat VALUES (%s,NOW(),%s,%s) ON CONFLICT (exchange) DO UPDATE SET last_seen=NOW(), live_markets=EXCLUDED.live_markets, note=EXCLUDED.note",(name,live,note))'''
if old2 in s: s=s.replace(old2,new2,1); n+=1
if 'LAST_ERR={}' not in s: s=s.replace("SM_TOK=None; SM_T=0","LAST_ERR={}\nSM_TOK=None; SM_T=0",1); n+=1
s2=re.sub(r'print\("markets chunk error",repr\(e\)\[:\d+\],flush=True\)',r'print("markets chunk error",repr(e)[:120],flush=True); LAST_ERR["smarkets"]=repr(e)',s); n+=int(s2!=s); s=s2
open(p,'w').write(s); print("patches:",n)
print("markets calls now:",re.findall(r'sm\(f"events/[^)]*\)',s)[:2])
PY
python3 -m py_compile /root/pe-xx/xx_recorder.py
pkill -f xx_recorder.py || true; sleep 3; nohup /root/pe-xx/keepalive.sh >/dev/null 2>&1 &
sleep 90; pgrep -af xx_recorder.py | head -1; tail -4 /root/pe-xx/recorder.log
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
k=psycopg2.connect(DB,sslmode='require').cursor()
k.execute("SELECT exchange, count(*), max(ts) FROM xx_tape WHERE ts>now()-interval '3 minutes' GROUP BY exchange"); print("rows last 3 min:",k.fetchall())
k.execute("SELECT * FROM xx_heartbeat"); print(k.fetchall())
k.execute("SELECT event_name, market_name, sel_name, back_px, lay_px FROM xx_tape WHERE exchange='smarkets' ORDER BY ts DESC LIMIT 5"); [print("  ",r) for r in k.fetchall()]
PY
