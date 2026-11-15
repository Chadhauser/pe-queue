#!/bin/bash
# 583 (Sun 15 Nov 2026, 15:20). The runner saw no new job from 10:20 to 15:17 because its `git pull` was refused (untracked files in
# /root/pe-queue that the repository also contained) and the error was swallowed. The break check never noticed because the "job"
# heartbeat is written by progress.sh, not by the runner's loop. Fixes, all in the runner and the break check:
#  1. runner.sh: after the pull, if HEAD != origin/main, move aside every untracked file that origin/main also contains and pull again;
#     write /root/pe-queue-state/runner_cycle (touched every cycle that reaches the job loop) and runner_head (HEAD after pull).
#  2. break_check.sh: BREAK + heal if runner_cycle is older than 10 min (runner not cycling), or if a jobs/*.sh on origin/main is neither
#     in done/ nor waiting/ nor currently running for more than 30 min (runner not picking up) — heal = the same aside-and-pull.
set -o pipefail
R=/root/pe-queue/runner/runner.sh; cp $R $R.bak_583
python3 - <<'PY'
p='/root/pe-queue/runner/runner.sh'; s=open(p).read(); assert '583' not in s
old="git pull -q --no-edit 2>>/root/pe-queue-state/git.err || true\n"
new='''git pull -q --no-edit 2>>/root/pe-queue-state/git.err || true
# 583: a refused pull must not leave the runner blind. If we are behind origin/main, move aside untracked files the repo also holds and pull again.
git fetch -q origin 2>>/root/pe-queue-state/git.err || true
if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ] && ! git merge-base --is-ancestor origin/main HEAD 2>/dev/null; then
  mkdir -p /root/pe-queue-state/aside
  git ls-files --others --exclude-standard | while read f; do git cat-file -e origin/main:"$f" 2>/dev/null && { mkdir -p "/root/pe-queue-state/aside/$(dirname "$f")"; mv "$f" "/root/pe-queue-state/aside/$f"; echo "$(date -u +%FT%H:%M) aside: $f" >> /root/pe-queue-state/git.err; }; done
  git merge --abort 2>/dev/null; git rebase --abort 2>/dev/null
  git pull -q --no-rebase --no-edit -X theirs 2>>/root/pe-queue-state/git.err || echo "$(date -u +%FT%H:%M) pull still failing after aside" >> /root/pe-queue-state/git.err
fi
git rev-parse --short HEAD > /root/pe-queue-state/runner_head 2>/dev/null; touch /root/pe-queue-state/runner_cycle
'''
assert old in s; s=s.replace(old,new,1); open(p,'w').write(s); print("runner: self-healing pull + cycle marker")
PY
bash -n $R && echo "runner compiles" || { cp $R.bak_583 $R; echo "RESTORED runner"; exit 1; }
S=/root/pe-sports/team/break_check.sh; cp $S $S.bak_583
python3 - <<'PY'
p='/root/pe-sports/team/break_check.sh'; s=open(p).read(); assert '583' not in s
add='''# 583: the job runner itself — is it cycling, and is it picking up new jobs?
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
'''
a='pgrep -f bookie_v2.py >/dev/null'; assert a in s; s=s.replace(a,add+a,1); open(p,'w').write(s); print("break_check: runner liveness + pickup")
PY
bash -n $S && echo "break_check compiles" || { cp $S.bak_583 $S; echo "RESTORED break_check"; }
# the runner records which job it is on, so the pickup check does not flag the job currently running
python3 - <<'PY'
p='/root/pe-queue/runner/runner.sh'; s=open(p).read()
old='  python3 /root/pe-queue/runner/report.py start "$name"\n'
if 'runner_current' not in s and old in s: s=s.replace(old, old+'  echo "$name" > /root/pe-queue-state/runner_current\n',1); open(p,'w').write(s); print("runner: records current job")
PY
bash -n /root/pe-queue/runner/runner.sh && echo "runner compiles (2)" || { cp $R.bak_583 $R; echo RESTORED; }
echo "git.err tail:"; tail -5 /root/pe-queue-state/git.err 2>/dev/null | cut -c1-200
echo "aside now:"; find /root/pe-queue-state/aside -type f 2>/dev/null | head -10
echo "583 done"
