#!/bin/bash
# FIN RUNNER — the financial chat's OWN job runner, separate from the shared pe-queue runner (sports).
# Terms (Peter / sports chat, 16 Nov 2026): own queue (fin/jobs/*.sh in its own clone at /root/pe-finq/repo), lowest priority
# (nice 19 + ionice idle), 30-minute hard cap per job, stops itself under 25 GB free disk, unset GITHUB_TOKEN before any push,
# no Wine or MetaTrader. Cron: */2 * * * * nice -n 19 ionice -c3 /root/pe-finq/repo/fin/runner/fin_runner.sh
unset GITHUB_TOKEN
R=/root/pe-finq/repo; S=/root/pe-finq/state; mkdir -p $S/done $S/logs
exec 9>$S/runner.lock; flock -n 9 || exit 0
cd $R || exit 1
git pull -q --rebase origin main 2>>$S/git.err || { git rebase --abort 2>/dev/null; git reset -q --hard origin/main; }
disk_ok(){ local g; g=$(df -BG --output=avail / | tail -1 | tr -dc 0-9); [ "$g" -ge 25 ] && return 0
  echo "$(date -u +%FT%H:%M) STOPPED: ${g} GB free < 25 GB" >> $S/stops.log; return 1; }
publish(){
  mkdir -p fin/reports/jobs
  [ -f $S/bots/bots.md ] && { tail -n +2 $S/bots/bots.md > $S/bots_body.new; cmp -s $S/bots_body.new $S/bots_body.last || { cp $S/bots/bots.md fin/reports/bots.md; cp $S/bots_body.new $S/bots_body.last; }; }
  [ -f $S/bots/bots.log ] && tail -60 $S/bots/bots.log > fin/reports/bots_log_tail.txt
  [ -f $S/stops.log ] && tail -20 $S/stops.log > fin/reports/stops.txt
  for f in league.md league_paper.md league_trades_today.md; do                      # league files: copy only when the content (not the timestamp) changed
    [ -f $S/league/$f ] || continue
    grep -v '^updated ' $S/league/$f > $S/league_$f.new
    cmp -s $S/league_$f.new $S/league_$f.last || { cp $S/league/$f fin/reports/$f; cp $S/league_$f.new $S/league_$f.last; }
  done
  git add fin/reports >/dev/null 2>&1
  git diff --cached --quiet && return 0
  git commit -qm "fin reports $(date -u +%FT%H:%M)" && { git pull -q --rebase origin main 2>>$S/git.err; git push -q origin HEAD:main 2>>$S/git.err; }
}
disk_ok || { publish; exit 0; }
for job in $(ls fin/jobs/*.sh 2>/dev/null | sort); do
  n=$(basename "$job" .sh); [ -f "$S/done/$n" ] && continue
  disk_ok || break
  start=$(date +%s)
  timeout -k 30 1800 nice -n 19 ionice -c3 bash "$job" 9>&- > "$S/logs/$n.log" 2>&1; rc=$?
  [ "$rc" = "124" ] && echo "TIMEOUT: killed at the 30-minute cap" >> "$S/logs/$n.log"
  echo "exit=$rc secs=$(( $(date +%s) - start ))" >> "$S/logs/$n.log"
  touch "$S/done/$n"; mkdir -p fin/reports/jobs; tail -c 20000 "$S/logs/$n.log" > "fin/reports/jobs/$n.log"
  publish
done
publish
