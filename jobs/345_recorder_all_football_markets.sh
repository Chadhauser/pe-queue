#!/bin/bash
# 345: FULL FOOTBALL MARKET SET ON THE TAPE. liq_recorder.py records 8 market types; the exchange runs ~25 on every game.
# Add corners, booking points, next goal, HT family, team goals, total-goals bands, derivatives (double chance, clean sheet,
# win to nil, winning margin, HT/FT) so the relative-value, corners/cards and HT tests have data. Patches the market-type
# literal in place (backup kept), restarts via its keepalive. The table gets bigger; it moves to the local Postgres in the next step.
set -o pipefail
F=/root/pe-liq/liq_recorder.py; cp -n $F $F.bak_$(date +%F)
python3 - <<'PY'
import re
p='/root/pe-liq/liq_recorder.py'; s=open(p).read()
m=re.search(r"(\[\s*'MATCH_ODDS'[^\]]*\])",s)
if not m: print("market-type literal not found; no change"); raise SystemExit(0)
ADD=['MATCH_ODDS','OVER_UNDER_05','OVER_UNDER_15','OVER_UNDER_25','OVER_UNDER_35','OVER_UNDER_45','OVER_UNDER_55','BOTH_TEAMS_TO_SCORE','CORRECT_SCORE','ASIAN_HANDICAP','DRAW_NO_BET',
 'HALF_TIME','HALF_TIME_SCORE','HALF_TIME_FULL_TIME','FIRST_HALF_GOALS_05','FIRST_HALF_GOALS_15','FIRST_HALF_GOALS_25','SECOND_HALF_GOALS_05','SECOND_HALF_GOALS_15',
 'NEXT_GOAL','TEAM_A_OVER_UNDER_05','TEAM_A_OVER_UNDER_15','TEAM_A_OVER_UNDER_25','TEAM_B_OVER_UNDER_05','TEAM_B_OVER_UNDER_15','TEAM_B_OVER_UNDER_25',
 'TOTAL_GOALS','EXACT_GOALS','WINNING_MARGIN','DOUBLE_CHANCE','CLEAN_SHEET','TEAM_A_WIN_TO_NIL','TEAM_B_WIN_TO_NIL','MATCH_ODDS_AND_BTTS','MATCH_ODDS_AND_OU_25',
 'CORNER_ODDS','OVER_UNDER_CORNERS','ALT_CORNERS','CORNER_HANDICAP','BOOKING_ODDS','OVER_UNDER_BOOKING_POINTS','ALT_BOOKINGS','PENALTY_TAKEN','SENDING_OFF','GOAL_LINE','ASIAN_HANDICAP_HT']
old=m.group(1); cur=re.findall(r"'([A-Z_0-9]+)'",old); new=cur+[a for a in ADD if a not in cur]
s=s.replace(old,"["+",".join(f"'{x}'" for x in new)+"]",1); open(p,'w').write(s)
print(f"market types {len(cur)} -> {len(new)}")
PY
python3 -m py_compile /root/pe-liq/liq_recorder.py || { cp /root/pe-liq/liq_recorder.py.bak_$(date +%F) /root/pe-liq/liq_recorder.py; echo "compile failed, restored"; exit 1; }
echo "== how the recorder names mkt for unknown types (it must not drop them)"; grep -n -E "mkt\s*=|def .*mkt|marketType" /root/pe-liq/liq_recorder.py | head -8
pkill -f liq_recorder.py; sleep 3   # keepalive (cron, every minute) relaunches it
sleep 120; python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
cur=psycopg2.connect(creds.pg_railway(), sslmode='require').cursor(); cur.execute("SET statement_timeout='120s'")
cur.execute("select mkt, count(*) from liq_sample where ts > now()-interval '3 minutes' group by 1 order by 2 desc"); print(cur.fetchall())
PY
