#!/bin/bash
# 344: PLAYER MARKETS ON THE TAPE. Betfair exchange TO_SCORE (anytime scorer), FIRST_GOAL_SCORER, TO_SCORE_2_OR_MORE on every
# football event from 6 h pre-KO through in-play, best 3 levels + sizes + ltp + matched, every 60 s. New recorder under
# /root/pe-player built from liq_recorder.py's login/session code (so it reads creds the same way), table player_liq.
# Step 1 (this job, report-first): print how liq_recorder.py logs in, lists markets and writes rows, so the recorder is
# built on the proven code path; then build and start it if the three anchors are found.
set -o pipefail
F=/root/pe-liq/liq_recorder.py
[ -f $F ] || { echo "missing $F"; exit 1; }
echo "== anchors in liq_recorder.py (line numbers only)"
grep -n -E "def |listMarketCatalogue|marketTypeCodes|listMarketBook|MARKET_TYPES|market_types|INSERT INTO liq_sample|keepalive|login|sessionToken|X-Application" $F | sed -E 's#postgres(ql)?://[^ ]*#<dsn>#g' | head -40
echo "== market types used"; grep -n -oE "'[A-Z_0-9]+'" $F | grep -E "MATCH_ODDS|OVER_UNDER|CORRECT_SCORE|ASIAN|DRAW_NO|BOTH_TEAMS" | sort | uniq -c | head
echo "== row shape"; grep -n -A6 "INSERT INTO liq_sample" $F | head -12
echo "== try the derived recorder"
python3 - <<'PY'
import re,sys,os
src=open('/root/pe-liq/liq_recorder.py').read()
need=['listMarketCatalogue','listMarketBook','INSERT INTO liq_sample']
missing=[n for n in need if n not in src]
if missing: print("cannot derive automatically, anchors missing:",missing); sys.exit(0)
# 1) market types -> player types; 2) table -> player_liq; 3) heartbeat table if present
out=src
mt=re.search(r"(\[\s*'MATCH_ODDS'[^\]]*\])",src)
if not mt: print("market-type list not found as a literal; manual patch needed"); sys.exit(0)
out=out.replace(mt.group(1),"['TO_SCORE','FIRST_GOAL_SCORER','TO_SCORE_2_OR_MORE']")
out=out.replace('liq_sample','player_liq').replace('liq_heartbeat','player_heartbeat')
os.makedirs('/root/pe-player',exist_ok=True); open('/root/pe-player/player_recorder.py','w').write(out)
print("derived /root/pe-player/player_recorder.py; market types replaced:",mt.group(1)[:80])
PY
[ -f /root/pe-player/player_recorder.py ] || { echo "no recorder built; manual patch job follows"; exit 0; }
python3 -m py_compile /root/pe-player/player_recorder.py || exit 1
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
con=psycopg2.connect(creds.pg_railway(), sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("CREATE TABLE IF NOT EXISTS player_liq (LIKE liq_sample INCLUDING ALL)")
cur.execute("CREATE TABLE IF NOT EXISTS player_heartbeat (LIKE liq_heartbeat INCLUDING ALL)") if True else None
print("tables ready")
PY
cat > /root/pe-player/keepalive_player.sh <<'SH'
#!/bin/bash
while true; do python3 /root/pe-player/player_recorder.py >> /root/pe-player/player.log 2>&1; sleep 15; done
SH
chmod +x /root/pe-player/keepalive_player.sh
pkill -f keepalive_player.sh 2>/dev/null; pkill -f player_recorder.py 2>/dev/null; sleep 1
nohup /root/pe-player/keepalive_player.sh >/dev/null 2>&1 &
( crontab -l 2>/dev/null | grep -v keepalive_player; echo "@reboot nohup /root/pe-player/keepalive_player.sh >/dev/null 2>&1 &"; echo "*/10 * * * * pgrep -f keepalive_player.sh >/dev/null || nohup /root/pe-player/keepalive_player.sh >/dev/null 2>&1 &" ) | crontab -
sleep 90; echo "== first rows"; python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
cur=psycopg2.connect(creds.pg_railway(), sslmode='require').cursor()
cur.execute("select mkt, count(*), count(distinct event_name) from player_liq group by 1"); print(cur.fetchall())
PY
tail -5 /root/pe-player/player.log | sed -E 's#postgres(ql)?://[^ ]*#<dsn>#g'
