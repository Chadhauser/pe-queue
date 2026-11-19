#!/bin/bash
# 661 (Thu 19 Nov 2026, 07:10). 660 found the cause: the server rebooted 18 Nov 10:15 UTC and NONE of the keepalive crons restarted
# their daemon for 21 hours. Bug: cron runs `sh -c "pgrep -f book_recorder.py || nohup ..."`, and pgrep -f matches that sh -c line
# itself (its command line contains the name), so the check always "finds" the daemon and never restarts it. Fix: bracket the first
# letter ('[b]ook_recorder.py' matches the process but not its own text). Applied to every keepalive line of ours; crontab backed up.
# Proof: the old pattern finds a process that does not exist; the new one does not; the new one still finds the running recorder.
R=/root/pe-queue/reports/keepalive_661.md
{ echo "# 661 — $(date -u '+%F %H:%M') UTC"; echo '```'
echo "== proof of the bug and the fix"
sh -c "pgrep -f nosuch_proc_661.py >/dev/null && echo 'OLD pattern: FOUND a process that does not exist (the bug)' || echo 'OLD pattern: not found'"
sh -c "pgrep -f '[n]osuch_proc_661.py' >/dev/null && echo 'NEW pattern: found (wrong)' || echo 'NEW pattern: not found (correct)'"
sh -c "pgrep -f '[b]ook_recorder.py' >/dev/null && echo 'NEW pattern on running recorder: found (correct)' || echo 'NEW pattern on running recorder: NOT found (wrong)'"
mkdir -p /root/pe-queue/.cache 2>/dev/null; crontab -l > /root/crontab.bak_661
python3 - <<'PY'
import re, subprocess
s = open('/root/crontab.bak_661').read(); out = []; n = 0
for line in s.splitlines():
    m = re.match(r"^(.*?pgrep -f )('?)([^' >]+)('?)( *>/dev/null \|\|.*)$", line)
    if m and not m.group(3).startswith('['):
        name = m.group(3); line = f"{m.group(1)}'[{name[0]}]{name[1:]}'{m.group(5)}"; n += 1
    out.append(line)
open('/root/crontab.new_661', 'w').write("\n".join(out) + "\n"); print("keepalive lines fixed:", n)
PY
crontab /root/crontab.new_661 && echo "crontab installed"
echo "== keepalive lines now"; crontab -l | grep 'pgrep -f' | cut -c1-170
echo "== run every keepalive line once by hand: nothing should double-start"
crontab -l | grep 'pgrep -f' | sed 's/^[^ ]* [^ ]* [^ ]* [^ ]* [^ ]* //' | while read -r cmd; do sh -c "$cmd"; done; sleep 5
for p in book_recorder small_bites_live coherence_paper v3_recorder monitor_ht bookie_v2; do echo "$p: $(pgrep -fc "[${p:0:1}]${p:1}\.py") process(es)"; done
echo '```'; } > $R 2>&1
cd /root/pe-queue && git add $R && git commit -qm "661: keepalive fix" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
