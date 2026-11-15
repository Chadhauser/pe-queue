#!/bin/bash
# 591 (Sun 15 Nov 2026, 17:00). Rewrite break_check.sh lines 67-90 cleanly: 583's runner block was spliced into the middle of 574's `if`
# (same anchor text), so the restart branch fired whenever the bot process existed and killed the bot at 15:20 and 16:20. Also 574's
# heartbeat query named a column (ts) bookie_heartbeat does not have, so HB was always -1. New block: runner check, then heartbeat age
# from the table's own timestamp column, then restart only when HB is a number >= 15.
set -o pipefail
S=/root/pe-sports/team/break_check.sh; cp $S $S.bak_591
python3 - <<'PY'
p='/root/pe-sports/team/break_check.sh'; s=open(p).read()
i=s.index('# 574: bot liveness from its own heartbeat row'); j=s.index('pgrep -f bookie_v2.py >/dev/null || B="$B bot process not running;"')
assert i<j
new='''# 583: the job runner itself — is it cycling, and is it picking up new jobs?
RC=/root/pe-queue-state/runner_cycle
if [ -f "$RC" ] && [ $(( $(date +%s) - $(stat -c %Y "$RC") )) -gt 600 ]; then B="$B job runner not cycling for $(( ( $(date +%s) - $(stat -c %Y "$RC") ) / 60 )) min (lock held or hung);"; fi
cd /root/pe-queue && git fetch -q origin 2>/dev/null
STALE=$(git ls-tree --name-only origin/main jobs/ 2>/dev/null | while read j; do n=$(basename "$j" .sh); [ -f /root/pe-queue-state/done/$n ] || [ -f /root/pe-queue-state/waiting/$n ] || { t=$(git log -1 --format=%ct origin/main -- "$j" 2>/dev/null); [ -n "$t" ] && [ $(( $(date +%s) - t )) -gt 1800 ] && ! grep -q "$n" /root/pe-queue-state/runner_current 2>/dev/null && echo "$n"; }; done | head -3 | tr '\\n' ' ')
if [ -n "$STALE" ]; then
  if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]; then
    mkdir -p /root/pe-queue-state/aside; git ls-files --others --exclude-standard | while read f; do git cat-file -e origin/main:"$f" 2>/dev/null && { mkdir -p "/root/pe-queue-state/aside/$(dirname "$f")"; mv "$f" "/root/pe-queue-state/aside/$f"; }; done
    git merge --abort 2>/dev/null; git rebase --abort 2>/dev/null; git pull -q --no-rebase --no-edit -X theirs 2>/dev/null && HEALED="$HEALED runner clone was behind origin (jobs $STALE unseen) - pulled;" || B="$B runner clone behind origin and pull still refused (jobs $STALE unseen);"
  else B="$B jobs on origin older than 30 min not run and not waiting: $STALE;"; fi
fi
cd /root/pe-sports/team
# 574/591: bot liveness from its own heartbeat row (fresh within 15 min = alive); stale + process present -> restart first, email only if still stale next hour
HB=$(python3 - <<'PYH'
import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
try:
    c=psycopg2.connect(creds.pg_local(),sslmode='disable',connect_timeout=10).cursor(); c.execute("SET statement_timeout='30s'")
    c.execute("select column_name from information_schema.columns where table_name='bookie_heartbeat' and data_type like 'timestamp%' order by ordinal_position limit 1"); col=c.fetchone()[0]
    c.execute(f"select extract(epoch from now()-max({col}))/60 from bookie_heartbeat"); v=c.fetchone()[0]; print(int(v) if v is not None else 9999)
except Exception: print(-1)
PYH
)
if [ "${HB:--1}" -ge 15 ] && pgrep -f bookie_v2.py >/dev/null; then
  if ls /root/pe-sports/team/bot_restarted_$(date -u -d '-60 minutes' +%F_%H) /root/pe-sports/team/bot_restarted_$(date -u +%F_%H) >/dev/null 2>&1; then B="$B bot heartbeat $HB minutes old an hour after a restart;"; else pkill -f "python3 bookie_v2.py"; touch /root/pe-sports/team/bot_restarted_$(date -u +%F_%H); HEALED="$HEALED restarted the bot (heartbeat $HB min old);"; fi
fi
[ "${HB:--1}" = "-1" ] && B="$B bot heartbeat unreadable (query failed);"
'''
s=s[:i]+new+s[j:]; open(p,'w').write(s); print("block rewritten")
PY
bash -n $S && echo "break_check compiles" || { cp $S.bak_591 $S; echo RESTORED; exit 1; }
grep -c "583: the job runner" $S; grep -n "^if \[ \"\${HB" $S | cut -c1-120
echo "--- heartbeat age now:"; python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
c=psycopg2.connect(creds.pg_local(),sslmode='disable').cursor()
c.execute("select column_name from information_schema.columns where table_name='bookie_heartbeat' order by ordinal_position"); print([r[0] for r in c.fetchall()])
c.execute("select column_name from information_schema.columns where table_name='bookie_heartbeat' and data_type like 'timestamp%' order by ordinal_position limit 1"); col=c.fetchone()[0]
c.execute(f"select extract(epoch from now()-max({col}))/60 from bookie_heartbeat"); print("age min:",c.fetchone()[0])
PY
echo "--- dry run of the check (no kill expected):"; bash $S; echo "exit $?"; tail -2 /root/pe-queue/reports/breaks.md | cut -c1-200
echo "591 done"
