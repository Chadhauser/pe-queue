#!/bin/bash
# 573 (Sat 14 Nov 2026, 10:10). The 09:20 email: "bot process present but not reading its cells for 30 minutes". Read what the bot is
# doing (log tail with timestamps, process state, heartbeat), restart it if it is wedged, and make the break check HEAL this case itself
# (restart the bot under its keepalive) and email only if the bot is still silent an hour later.
set -o pipefail
L=/root/pe-sports/bookie/bookie_v2.log
echo "== bot now =="; pgrep -fa "bookie_v2" | cut -c1-100; for p in $(pgrep -f "python3 bookie_v2.py"); do echo "pid $p state $(ps -o stat=,etimes=,rss= -p $p)"; done
echo "--- last 25 log lines"; tail -25 $L | cut -c1-200
echo "--- 'passed cells' lines in the last 2 h: $(awk -v s="$(date -u -d '-120 minutes' '+%Y-%m-%d %H:%M')" '$1 ~ /^20[0-9][0-9]-/ {keep=($1" "$2>=s)} keep' $L | grep -c 'passed cells')"
echo "--- tracebacks in the last 2 h: $(awk -v s="$(date -u -d '-120 minutes' '+%Y-%m-%d %H:%M')" '$1 ~ /^20[0-9][0-9]-/ {keep=($1" "$2>=s)} keep' $L | grep -c Traceback)"
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
c=psycopg2.connect(creds.pg_local(),sslmode='disable').cursor()
c.execute("select * from bookie_heartbeat order by 2 desc limit 3"); print("heartbeat:",c.fetchall())
c.execute("select count(*), max(ts) from bookie_paper where version='v2' and ts>now()-interval '12 hours'"); print("paper orders 12 h:",c.fetchone())
c.execute("select count(distinct market_id) from liq_sample where mkt='MO' and ts>now()-interval '2 hours'"); print("match-odds markets on the tape 2 h:",c.fetchone()[0])
PY
if [ "$(awk -v s="$(date -u -d '-30 minutes' '+%Y-%m-%d %H:%M')" '$1 ~ /^20[0-9][0-9]-/ {keep=($1" "$2>=s)} keep' $L | grep -c 'passed cells')" = 0 ]; then
  echo "bot silent 30 min -> restart"; pkill -f "python3 bookie_v2.py"; sleep 45; pgrep -fa "python3 bookie_v2.py" | cut -c1-80; tail -4 $L | cut -c1-200
else echo "bot is reading its cells now"; fi
echo "== break check heals the bot itself =="
S=/root/pe-sports/team/break_check.sh; cp $S $S.bak_573
python3 - <<'PY'
p='/root/pe-sports/team/break_check.sh'; s=open(p).read(); assert '573' not in s
old='''[ "${ALIVE:-0}" = 0 ] && pgrep -f bookie_v2.py >/dev/null && B="$B bot process present but not reading its cells for 30 minutes;"'''
new='''if [ "${ALIVE:-0}" = 0 ] && pgrep -f bookie_v2.py >/dev/null; then   # 573: heal first — restart under the keepalive; email only if still silent next hour
  if [ -f /root/pe-sports/team/bot_restarted_$(date -u -d '-60 minutes' +%F_%H) ] || [ -f /root/pe-sports/team/bot_restarted_$(date -u +%F_%H) ]; then B="$B bot restarted an hour ago and still not reading its cells;"; else pkill -f "python3 bookie_v2.py"; touch /root/pe-sports/team/bot_restarted_$(date -u +%F_%H); HEALED="$HEALED restarted the bot (no cells read for 30 min);"; fi
fi'''
assert old in s; s=s.replace(old,new,1); open(p,'w').write(s); print("break_check: bot liveness heals itself")
PY
bash -n $S && echo "break_check compiles" || { cp $S.bak_573 $S; echo RESTORED; }
echo "573 done"
