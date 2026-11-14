#!/bin/bash
# 574 (Sat 14 Nov 2026, 10:55). The 09:20 and 10:20 emails were FALSE: 573 read the bot's log — "passed cells" every ten minutes all
# morning, 12 in the last two hours, no tracebacks — while the check's log-window test returned zero. 573's heal patch also failed to
# find its anchor. Stop testing the log: liveness comes from the bot's own heartbeat row in the database (fresh within 15 minutes = alive);
# a stale heartbeat with the process present -> restart under the keepalive, email only if still stale an hour later.
set -o pipefail
S=/root/pe-sports/team/break_check.sh; cp $S $S.bak_574
echo "--- current liveness lines:"; grep -n "ALIVE\|SINCE30\|not reading its cells" $S | cut -c1-200
python3 - <<'PY'
import re
p='/root/pe-sports/team/break_check.sh'; s=open(p).read()
lines=s.split('\n'); out=[]; dropped=0
for l in lines:
    if 'ALIVE=' in l or 'not reading its cells' in l or ('SINCE30' in l and 'SINCE=' not in l): dropped+=1; continue
    out.append(l)
s='\n'.join(out)
s=s.replace("SINCE=$(date -u -d '-60 minutes' '+%Y-%m-%d %H:%M'); SINCE30=$(date -u -d '-30 minutes' '+%Y-%m-%d %H:%M')","SINCE=$(date -u -d '-60 minutes' '+%Y-%m-%d %H:%M')")
add='''# 574: bot liveness from its own heartbeat row (fresh within 15 min = alive); stale + process present -> restart first, email only if still stale next hour
HB=$(python3 - <<'PYH'
import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
try:
    c=psycopg2.connect(creds.pg_local(),sslmode='disable',connect_timeout=10).cursor(); c.execute("select extract(epoch from now()-max(ts))/60 from bookie_heartbeat"); print(int(c.fetchone()[0] or 9999))
except Exception: print(-1)
PYH
)
if [ "${HB:--1}" -ge 15 ] && pgrep -f bookie_v2.py >/dev/null; then
  if ls /root/pe-sports/team/bot_restarted_$(date -u -d '-60 minutes' +%F_%H) /root/pe-sports/team/bot_restarted_$(date -u +%F_%H) >/dev/null 2>&1; then B="$B bot heartbeat $HB minutes old an hour after a restart;"; else pkill -f "python3 bookie_v2.py"; touch /root/pe-sports/team/bot_restarted_$(date -u +%F_%H); HEALED="$HEALED restarted the bot (heartbeat $HB min old);"; fi
fi
'''
a='pgrep -f bookie_v2.py >/dev/null || B='
assert a in s, "anchor"; s=s.replace(a,add+a,1); open(p,'w').write(s); print("dropped",dropped,"log-window liveness lines; heartbeat liveness added")
PY
bash -n $S && echo "break_check compiles" || { cp $S.bak_574 $S; echo RESTORED; exit 1; }
grep -n "bookie_heartbeat\|not reading" $S | cut -c1-120
bash $S; echo "break check exit $? — expected: no email (bot heartbeat fresh)"
echo "574 done"
