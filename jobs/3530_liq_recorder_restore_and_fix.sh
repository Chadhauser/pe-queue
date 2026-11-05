#!/bin/bash
# 359: URGENT. 352's patch crashes liq_recorder.py at line 47 (KeyError: new market type in a fallback dict lookup `[mt]`).
# Step 1: restore the pre-patch backup and start the recorder (tape back within a minute). Step 2: apply the patch again on
# a copy, replace every `}[mt]` fallback with `}.get(mt,mt)`, run the copy for 90 s in a dry test (import + one catalogue
# refresh), and only if it survives swap it in. Acceptance: heartbeat timestamp AFTER the restart, no Traceback in liq.log.
set -o pipefail
F=/root/pe-liq/liq_recorder.py
B=$(ls -t /root/pe-liq/liq_recorder.py.bak_346_* 2>/dev/null | head -1); [ -n "$B" ] || { echo "no backup found"; exit 1; }
cp $F $F.crashed_$(date +%H%M); cp $B $F; echo "restored from $B"
rm -f /root/pe-liq/CRASH_LOOP /root/pe-liq/.crashloop 2>/dev/null
pkill -f liq_recorder.py; sleep 3; pgrep -f keepalive.sh >/dev/null || (cd /root/pe-liq && nohup ./keepalive.sh >/dev/null 2>&1 &)
T0=$(date -u +%s); sleep 75
python3 - <<'PY'
import sys,psycopg2,time; sys.path.insert(0,'/root/pe-queue/runner'); import creds
c=psycopg2.connect(creds.pg_railway(), sslmode='require').cursor(); c.execute("select extract(epoch from now()-max(last_seen)) from liq_heartbeat"); print("heartbeat age after restore (s):", round(c.fetchone()[0]))
PY
tail -3 /root/pe-liq/liq.log | sed -E 's#postgres(ql)?://[^ ]*#<dsn>#g'
echo "== step 2: corrected patch on a copy"
cp $F /root/pe-liq/liq_recorder_new.py
python3 - <<'PY'
import re
p='/root/pe-liq/liq_recorder_new.py'; s=open(p).read()
NEW={'OVER_UNDER_05':'OU05','OVER_UNDER_45':'OU45','OVER_UNDER_55':'OU55','HALF_TIME':'HT_MO','HALF_TIME_SCORE':'HT_CS','HALF_TIME_FULL_TIME':'HTFT','FIRST_HALF_GOALS_05':'FH05','FIRST_HALF_GOALS_15':'FH15','FIRST_HALF_GOALS_25':'FH25','SECOND_HALF_GOALS_05':'SH05','SECOND_HALF_GOALS_15':'SH15','NEXT_GOAL':'NG','TEAM_A_OVER_UNDER_05':'HOU05','TEAM_A_OVER_UNDER_15':'HOU15','TEAM_A_OVER_UNDER_25':'HOU25','TEAM_B_OVER_UNDER_05':'AOU05','TEAM_B_OVER_UNDER_15':'AOU15','TEAM_B_OVER_UNDER_25':'AOU25','TOTAL_GOALS':'TG','EXACT_GOALS':'EG','WINNING_MARGIN':'WM','DOUBLE_CHANCE':'DC','CLEAN_SHEET':'CSHEET','TEAM_A_WIN_TO_NIL':'HWTN','TEAM_B_WIN_TO_NIL':'AWTN','MATCH_ODDS_AND_BTTS':'MOBTTS','MATCH_ODDS_AND_OU_25':'MOOU25','CORNER_ODDS':'CORN_MO','OVER_UNDER_CORNERS':'CORN_OU','ALT_CORNERS':'CORN_ALT','CORNER_HANDICAP':'CORN_AH','BOOKING_ODDS':'BOOK_MO','OVER_UNDER_BOOKING_POINTS':'BOOK_OU','ALT_BOOKINGS':'BOOK_ALT','PENALTY_TAKEN':'PEN','SENDING_OFF':'RED','GOAL_LINE':'GL','ASIAN_HANDICAP_HT':'AH_HT'}
m=[m for m in re.finditer(r"[\[(](?:\s*'[A-Z_0-9]+'\s*,?)+\s*[\])]",s) if 'MATCH_ODDS' in m.group(0)][0]
cur=re.findall(r"'([A-Z_0-9]+)'",m.group(0)); s=s[:m.start()]+"["+",".join(f"'{x}'" for x in cur+[k for k in NEW if k not in cur])+"]"+s[m.end():]
# every short-name dict literal gets the new names, and every hard [mt] lookup on a dict literal becomes .get(mt,mt)
for d in list(re.finditer(r"\{'MATCH_ODDS':'MO'[^}]*\}",s))[::-1]:
    dd=d.group(0).rstrip('}')+"".join(f",'{k}':'{v}'" for k,v in NEW.items() if f"'{k}'" not in d.group(0))+"}"; s=s[:d.start()]+dd+s[d.end():]
n_fix=len(re.findall(r"\}\[mt\]",s)); s=re.sub(r"\}\[mt\]","}.get(mt,mt)",s)
n_fix2=len(re.findall(r"\}\[m\['marketType'\]\]",s)); s=re.sub(r"\}\[m\['marketType'\]\]","}.get(m['marketType'],m['marketType'])",s)
if '"inPlayOnly":True' in s:
    s=s.replace('"inPlayOnly":True','"marketStartTime":{"from":_win(-4),"to":_win(2)}',1)
    s=s.replace("def login():","def _win(h):\n    import datetime as _d; return (_d.datetime.utcnow()+_d.timedelta(hours=h)).strftime('%Y-%m-%dT%H:%M:%SZ')\n\ndef login():",1)
open(p,'w').write(s); print(f"copy patched: hard lookups fixed {n_fix}+{n_fix2}; remaining '[mt]' occurrences: {s.count('[mt]')}")
PY
python3 -m py_compile /root/pe-liq/liq_recorder_new.py || { echo "copy does not compile; original left running"; exit 1; }
echo "== dry test: import and one catalogue refresh in a subprocess (no writes)"
cd /root/pe-liq && timeout 120 python3 - <<'PY'
import importlib.util, sys, traceback
spec=importlib.util.spec_from_file_location("lr","/root/pe-liq/liq_recorder_new.py")
src=open("/root/pe-liq/liq_recorder_new.py").read()
# execute only up to the main loop: cut at the first 'while True' at column 0
head=src.split("\nwhile True",1)[0]
g={'__name__':'dry'}
try:
    exec(compile(head,"liq_recorder_new.py","exec"),g)
    g['refresh_catalogue'](); print("catalogue markets:",len(g['cat']), "types:",sorted({v['mkt'] for v in g['cat'].values()})[:50])
    print("DRY OK")
except Exception:
    traceback.print_exc(); print("DRY FAIL"); sys.exit(1)
PY
rc=$?; [ $rc -eq 0 ] || { echo "dry test failed; original recorder stays"; exit 1; }
cp $F $F.bak_359; cp /root/pe-liq/liq_recorder_new.py $F; pkill -f liq_recorder.py; sleep 90
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
c=psycopg2.connect(creds.pg_railway(), sslmode='require').cursor(); c.execute("select extract(epoch from now()-max(last_seen)), max(last_seen) from liq_heartbeat"); age,ls=c.fetchone(); print("heartbeat age after swap (s):", round(age), ls)
c.execute("select mkt, count(*) from liq_sample where ts>now()-interval '2 minutes' group by 1 order by 2 desc"); print("rows last 2 min:",c.fetchall())
open('/tmp/359_ok','w').write('1' if age<80 else '0')
PY
grep -c Traceback /root/pe-liq/liq.log | sed 's/^/tracebacks in log: /'; tail -2 /root/pe-liq/liq.log | sed -E 's#postgres(ql)?://[^ ]*#<dsn>#g'
[ "$(cat /tmp/359_ok)" = "1" ] || { cp $F.bak_359 $F; pkill -f liq_recorder.py; echo "HEARTBEAT NOT FRESH AFTER SWAP: restored"; exit 1; }
echo "patched recorder live"
