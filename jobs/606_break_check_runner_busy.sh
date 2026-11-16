#!/bin/bash
# 606 (Mon 16 Nov 2026, 12:15). "job runner not cycling for 76 min" fired while 527 was legitimately running under its 3 h cap. A busy
# runner is not a hung one: only flag when the cycle marker is stale AND no job has been started within the last 3 h.
set -o pipefail
S=/root/pe-sports/team/break_check.sh; cp $S $S.bak_606
python3 - <<'PY'
p='/root/pe-sports/team/break_check.sh'; s=open(p).read(); assert '606' not in s
old='if [ -f "$RC" ] && [ $(( $(date +%s) - $(stat -c %Y "$RC") )) -gt 600 ]; then'
new='CUR=/root/pe-queue-state/runner_current; BUSY=0; [ -f "$CUR" ] && [ $(( $(date +%s) - $(stat -c %Y "$CUR") )) -lt 11000 ] && BUSY=1   # 606: a job started under 3 h ago holds the lock legitimately\nif [ "$BUSY" = 0 ] && [ -f "$RC" ] && [ $(( $(date +%s) - $(stat -c %Y "$RC") )) -gt 600 ]; then'
assert old in s; s=s.replace(old,new,1); open(p,'w').write(s); print("patched")
PY
bash -n $S && echo compiles || { cp $S.bak_606 $S; echo RESTORED; }
echo "606 done"
