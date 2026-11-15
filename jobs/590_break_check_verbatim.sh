#!/bin/bash
# 590 (Sun 15 Nov 2026, 16:50). The hourly check has killed the bot at 15:20 and 16:20 with "heartbeat -1 min old": 583's block was
# spliced into the middle of 574's `if` line (same anchor text), so the restart branch fires whenever the bot process exists. Print the
# file verbatim (no secrets in it: it only sources nothing and reads creds via creds.py) so it can be rewritten cleanly, and stop the
# hourly kill now by neutralising that one branch until the rewrite lands.
set -o pipefail
S=/root/pe-sports/team/break_check.sh; cp $S $S.bak_590
R=/root/pe-queue/reports/break_check_2026-11-15.md
{ echo "# break_check.sh verbatim — $(date -u '+%F %H:%M') UTC (job 590)"; echo; echo '```bash'; grep -v -i "password\|secret\|token=" $S | cat -n | cut -c1-330; echo '```'; echo "lines: $(wc -l < $S)"; echo; echo "## bot_restarted markers"; ls /root/pe-sports/team/bot_restarted_* 2>/dev/null | tail -5; echo; echo "## heartbeat query by hand"; python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
try:
    c=psycopg2.connect(creds.pg_local(),sslmode='disable',connect_timeout=10).cursor(); c.execute("select extract(epoch from now()-max(ts))/60, max(ts), now() from bookie_heartbeat"); print(c.fetchone())
except Exception as e: print("ERR",e)
PY
} > $R 2>&1
# stop the hourly kill: the restart branch may only run when HB is a number >= 15
python3 - <<'PY'
p='/root/pe-sports/team/break_check.sh'; s=open(p).read()
old='pkill -f "python3 bookie_v2.py"; touch /root/pe-sports/team/bot_restarted_$(date -u +%F_%H); HEALED="$HEALED restarted the bot (heartbeat $HB min old);"'
new='if [ "${HB:--1}" -ge 15 ]; then pkill -f "python3 bookie_v2.py"; touch /root/pe-sports/team/bot_restarted_$(date -u +%F_%H); HEALED="$HEALED restarted the bot (heartbeat $HB min old);"; fi   # 590 guard'
n=s.count(old); s=s.replace(old,new); open(p,'w').write(s); print("guarded restart branches:",n)
PY
bash -n $S && echo "break_check compiles" || { cp $S.bak_590 $S; echo RESTORED; }
cd /root/pe-queue && git add reports/break_check_2026-11-15.md && git commit -q -m "590: break_check verbatim" && git pull -q --no-rebase --no-edit && git push -q && echo pushed
echo "590 done"
