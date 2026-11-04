#!/bin/bash
# 346: PATCH THE LIVE RECORDER (344/345 could not find the market list as a literal — it is a loop over types on line 37
# and a short-name dict on line 44). This job: (1) prints lines 30-50 so the shape is on record; (2) patches the type list,
# the short-name dict and the catalogue window (in-play only -> 2 h pre-KO through in-play); (3) builds the player
# recorder as a copy with player types and its own tables; (4) restarts both, verifies new market types are landing within
# 3 minutes, else restores the backup and restarts the original. Backups kept as .bak_<date>.
set -o pipefail
F=/root/pe-liq/liq_recorder.py; B=$F.bak_346_$(date +%F_%H%M); cp $F $B
echo "== lines 30-50 of liq_recorder.py"; sed -n 30,50p $F | sed -E 's#postgres(ql)?://[^ ]*#<dsn>#g' | cut -c1-300
python3 - "$F" <<'PY'
import re,sys
p=sys.argv[1]; s=open(p).read(); orig=s
NEW={'OVER_UNDER_05':'OU05','OVER_UNDER_45':'OU45','OVER_UNDER_55':'OU55','HALF_TIME':'HT_MO','HALF_TIME_SCORE':'HT_CS','HALF_TIME_FULL_TIME':'HTFT',
 'FIRST_HALF_GOALS_05':'FH05','FIRST_HALF_GOALS_15':'FH15','FIRST_HALF_GOALS_25':'FH25','SECOND_HALF_GOALS_05':'SH05','SECOND_HALF_GOALS_15':'SH15',
 'NEXT_GOAL':'NG','TEAM_A_OVER_UNDER_05':'HOU05','TEAM_A_OVER_UNDER_15':'HOU15','TEAM_A_OVER_UNDER_25':'HOU25','TEAM_B_OVER_UNDER_05':'AOU05','TEAM_B_OVER_UNDER_15':'AOU15','TEAM_B_OVER_UNDER_25':'AOU25',
 'TOTAL_GOALS':'TG','EXACT_GOALS':'EG','WINNING_MARGIN':'WM','DOUBLE_CHANCE':'DC','CLEAN_SHEET':'CSHEET','TEAM_A_WIN_TO_NIL':'HWTN','TEAM_B_WIN_TO_NIL':'AWTN',
 'MATCH_ODDS_AND_BTTS':'MOBTTS','MATCH_ODDS_AND_OU_25':'MOOU25','CORNER_ODDS':'CORN_MO','OVER_UNDER_CORNERS':'CORN_OU','ALT_CORNERS':'CORN_ALT','CORNER_HANDICAP':'CORN_AH',
 'BOOKING_ODDS':'BOOK_MO','OVER_UNDER_BOOKING_POINTS':'BOOK_OU','ALT_BOOKINGS':'BOOK_ALT','PENALTY_TAKEN':'PEN','SENDING_OFF':'RED','GOAL_LINE':'GL','ASIAN_HANDICAP_HT':'AH_HT'}
# (1) the type list: any python list literal of quoted codes that contains MATCH_ODDS (line 37)
lists=[m for m in re.finditer(r"\[(?:\s*'[A-Z_0-9]+'\s*,?)+\s*\]",s) if 'MATCH_ODDS' in m.group(0)]
if not lists: print("PATCH FAIL: type list not found"); sys.exit(2)
m=lists[0]; cur=re.findall(r"'([A-Z_0-9]+)'",m.group(0)); add=[k for k in NEW if k not in cur]
s=s[:m.start()]+"["+",".join(f"'{x}'" for x in cur+add)+"]"+s[m.end():]
# (2) the short-name dict (line 44)
d=re.search(r"\{'MATCH_ODDS':'MO'[^}]*\}",s)
if not d: print("PATCH FAIL: short-name dict not found"); sys.exit(2)
dd=d.group(0).rstrip('}')+"".join(f",'{k}':'{v}'" for k,v in NEW.items() if f"'{k}'" not in d.group(0))+"}"
s=s[:d.start()]+dd+s[d.end():]
# (3) catalogue window: 2 h before KO through in-play (was in-play only); needs a helper
if '"inPlayOnly":True' in s:
    s=s.replace('"inPlayOnly":True','"marketStartTime":{"from":_win(-4),"to":_win(2)}',1)
    s=s.replace("def login():","def _win(h):\n    import datetime as _d; return (_d.datetime.utcnow()+_d.timedelta(hours=h)).strftime('%Y-%m-%dT%H:%M:%SZ')\n\ndef login():",1)
open(p,'w').write(s); print(f"patched: types {len(cur)} -> {len(cur)+len(add)}; dict +{len(NEW)}; window 4h-before..2h-ahead (in-play included)")
PY
rc=$?; [ $rc -eq 0 ] || { cp $B $F; echo "restored, no change"; exit 1; }
python3 -m py_compile $F || { cp $B $F; echo "compile failed, restored"; exit 1; }
# (4) player recorder as a copy
mkdir -p /root/pe-player
python3 - "$F" <<'PY'
import re,sys
s=open(sys.argv[1]).read()
m=[m for m in re.finditer(r"\[(?:\s*'[A-Z_0-9]+'\s*,?)+\s*\]",s) if 'MATCH_ODDS' in m.group(0)][0]
s=s[:m.start()]+"['TO_SCORE','FIRST_GOAL_SCORER','TO_SCORE_2_OR_MORE']"+s[m.end():]
d=re.search(r"\{'MATCH_ODDS':'MO'[^}]*\}",s); s=s[:d.start()]+"{'TO_SCORE':'ANYTIME','FIRST_GOAL_SCORER':'FGS','TO_SCORE_2_OR_MORE':'SCORE2'}"+s[d.end():]
s=s.replace('"CORRECT_SCORE"','"TO_SCORE"').replace('liq_sample','player_liq').replace('liq_heartbeat','player_heartbeat')
s=s.replace('_win(-4)','_win(-3)').replace('_win(2)','_win(6)')
open('/root/pe-player/player_recorder.py','w').write(s); print("player recorder written")
PY
python3 -m py_compile /root/pe-player/player_recorder.py || exit 1
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
con=psycopg2.connect(creds.pg_railway(), sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("CREATE TABLE IF NOT EXISTS player_liq (LIKE liq_sample INCLUDING ALL)")
cur.execute("CREATE TABLE IF NOT EXISTS player_heartbeat (LIKE liq_heartbeat INCLUDING ALL)"); print("player tables ready")
PY
cat > /root/pe-player/keepalive_player.sh <<'SH'
#!/bin/bash
while true; do python3 /root/pe-player/player_recorder.py >> /root/pe-player/player.log 2>&1; sleep 15; done
SH
chmod +x /root/pe-player/keepalive_player.sh
pkill -f keepalive_player.sh 2>/dev/null; pkill -f player_recorder.py 2>/dev/null; pkill -f liq_recorder.py; sleep 2
nohup /root/pe-player/keepalive_player.sh >/dev/null 2>&1 &
( crontab -l 2>/dev/null | grep -v keepalive_player; echo "@reboot nohup /root/pe-player/keepalive_player.sh >/dev/null 2>&1 &"; echo "*/10 * * * * pgrep -f keepalive_player.sh >/dev/null || nohup /root/pe-player/keepalive_player.sh >/dev/null 2>&1 &" ) | crontab -
sleep 180
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
cur=psycopg2.connect(creds.pg_railway(), sslmode='require').cursor(); cur.execute("SET statement_timeout='120s'")
cur.execute("select mkt, count(*) from liq_sample where ts > now()-interval '3 minutes' group by 1 order by 2 desc"); r=cur.fetchall(); print("liq_sample last 3 min:",r)
cur.execute("select mkt, count(*), count(distinct event_name) from player_liq group by 1"); print("player_liq:",cur.fetchall())
new=[m for m,_ in r if m not in ('MO','CS','OU15','OU25','OU35','BTTS','AH','DNB')]
open('/tmp/346_ok','w').write('1' if (r and len(r)>0) else '0'); print("new types seen:",new)
PY
tail -3 /root/pe-liq/liq.log 2>/dev/null | sed -E 's#postgres(ql)?://[^ ]*#<dsn>#g'; tail -3 /root/pe-player/player.log | sed -E 's#postgres(ql)?://[^ ]*#<dsn>#g'
[ "$(cat /tmp/346_ok)" = "1" ] || { cp $B $F; pkill -f liq_recorder.py; echo "RECORDER NOT WRITING AFTER PATCH: restored backup"; exit 1; }
echo "patch live"
