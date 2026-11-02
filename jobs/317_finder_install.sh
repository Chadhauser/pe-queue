#!/bin/bash
# 317: THE FINDER — nightly Claude Code agent (02:40) that takes the next untested idea from watchman/FINDER_QUEUE.md, writes and runs
# the honest test as jobs/45N_*.sh, and pushes reports/finder_<date>.md. Brief: watchman/FINDER.md (pulled fresh every run).
# Same tool allow/deny list as the Watchman. Uses the claude binary path the Watchman installer recorded. No claude needed at install.
mkdir -p /root/pe-finder/runs /root/pe-queue/reports
CP=/root/pe-watchman/claude_path
[ -s "$CP" ] || { echo "claude_path missing — run jobs/314_watchman.sh from Claude Code first"; exit 1; }
cat > /root/pe-finder/run.sh <<'SH'
#!/bin/bash
export PATH=/root/.local/bin:/root/.npm-global/bin:/usr/local/bin:/usr/bin:/bin:$PATH HOME=/root
exec 9>/root/pe-finder/.lock; flock -n 9 || exit 0
cd /root/pe-queue && git pull --rebase -q 2>/dev/null || true
ts=$(date +%F_%H%M)
timeout -k 60 5700 $(cat /root/pe-watchman/claude_path) -p "$(cat /root/pe-queue/watchman/FINDER.md)" \
  --allowedTools "Read,Write,Edit,Glob,Grep,Bash(git *),Bash(python3 *),Bash(python *),Bash(psql *),Bash(ls *),Bash(cat *),Bash(head *),Bash(tail *),Bash(grep *),Bash(wc *),Bash(date *),Bash(cp *),Bash(bash -n *),Bash(bash jobs/*),Bash(timeout *),Bash(mkdir *),Bash(cd *),Bash(echo *),Bash(sort *),Bash(uniq *),Bash(awk *),Bash(sed -n *)" \
  --disallowedTools "Bash(rm *),Bash(kill *),Bash(pkill *),Bash(crontab *),Bash(nohup *),Bash(systemctl *),Bash(reboot *),Bash(shutdown *),Bash(curl *),Bash(wget *),Bash(ssh *),Bash(scp *),Bash(chmod *),Bash(chown *)" \
  --max-turns 120 --output-format text > /root/pe-finder/runs/$ts.log 2>&1
echo "exit=$? at $(date)" >> /root/pe-finder/runs/$ts.log
find /root/pe-finder/runs -name '*.log' -mtime +14 -delete
SH
chmod +x /root/pe-finder/run.sh
( crontab -l 2>/dev/null | grep -v pe-finder/run.sh; echo "40 2 * * * /root/pe-finder/run.sh" ) | crontab -
echo "finder cron: $(crontab -l | grep -c pe-finder) line(s) at 02:40 nightly; first run tonight"
# first run now, in the background, so tonight is not the first time it is exercised
nohup /root/pe-finder/run.sh >/dev/null 2>&1 &
echo "first finder run started in background — report lands in reports/finder_$(date +%F).md when done"
