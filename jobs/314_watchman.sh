#!/bin/bash
set -o pipefail
# 314 (re-run of 313: the brief now lives in the repo at watchman/WATCHMAN.md and is pulled before every run, so brief changes no longer need a manual install; hard tool allow-list — read/list/grep/git/python/psql only, no kill/rm/crontab/nohup; brief tightened: no fixes for missing-data failures, no fix in the first 10 minutes of a run) THE WATCHMAN — a Claude Code agent on the server, hourly, that does what used to wait for Claude + Peter's laptop:
# reads the last two hours of job results, fixes any failed job as a NEW numbered job (400-449 range, never editing the old one),
# re-queues it, checks the integrity table and heartbeats, and writes a one-page summary (survivors only). If git can push, the
# summary and any fixed jobs are pushed to pe-queue (reports/ folder) so the strategy chat reads them without the laptop.
# Hard rules in its brief: creds only via creds.py, never print a secret, never stop a daemon, never touch anything with 'live' money,
# never create Claude.ai scheduled tasks, never email. Runs under flock with a 50-minute cap. Requires Claude Code already logged in.
set -e
mkdir -p /root/pe-watchman/runs /root/pe-queue/reports
CL=$(command -v claude 2>/dev/null || ls /root/.local/bin/claude /usr/local/bin/claude /root/.npm-global/bin/claude /root/.claude/local/claude /usr/bin/claude 2>/dev/null | head -1)
[ -z "$CL" ] && CL=$(find / -xdev -maxdepth 6 -type f -name claude -perm -u+x 2>/dev/null | head -1)
[ -z "$CL" ] && CL=$(ls -d /home/*/.local/bin/claude /home/*/.npm-global/bin/claude 2>/dev/null | head -1)
[ -z "$CL" ] && { echo "claude binary not found anywhere on the box (searched PATH, /root, /home, / depth 6)"; which node npm; ls -la /root /home; exit 1; }
echo "claude at: $CL"; echo "$CL" > /root/pe-watchman/claude_path
cat > /root/pe-watchman/run.sh <<'SH'
#!/bin/bash
export PATH=/root/.local/bin:/root/.npm-global/bin:/usr/local/bin:/usr/bin:/bin:$PATH HOME=/root
exec 9>/root/pe-watchman/.lock; flock -n 9 || exit 0
cd /root/pe-queue && git pull --rebase -q 2>/dev/null || true
ts=$(date +%F_%H%M)
timeout -k 60 3000 $(cat /root/pe-watchman/claude_path) -p "$(cat /root/pe-queue/watchman/WATCHMAN.md)" --allowedTools "Read,Write,Edit,Glob,Grep,Bash(git *),Bash(python3 *),Bash(python *),Bash(psql *),Bash(ls *),Bash(cat *),Bash(head *),Bash(tail *),Bash(grep *),Bash(wc *),Bash(date *),Bash(cp *),Bash(bash -n *),Bash(mkdir *),Bash(cd *),Bash(echo *),Bash(sort *),Bash(uniq *),Bash(awk *),Bash(sed -n *)" --disallowedTools "Bash(rm *),Bash(kill *),Bash(pkill *),Bash(crontab *),Bash(nohup *),Bash(systemctl *),Bash(reboot *),Bash(shutdown *),Bash(curl *),Bash(wget *),Bash(ssh *),Bash(scp *),Bash(chmod *),Bash(chown *)" --max-turns 60 --output-format text > /root/pe-watchman/runs/$ts.log 2>&1
echo "exit=$? at $(date)" >> /root/pe-watchman/runs/$ts.log
find /root/pe-watchman/runs -name '*.log' -mtime +7 -delete
SH
chmod +x /root/pe-watchman/run.sh; touch /root/pe-watchman/handled.txt
( crontab -l 2>/dev/null | grep -v pe-watchman/run.sh; echo "17 * * * * /root/pe-watchman/run.sh" ) | crontab -
echo "installed: $(crontab -l | grep -c pe-watchman) cron line(s); claude = $CL; version: $($CL --version 2>&1 | head -1)"; $CL -p "reply with the single word READY" --output-format text --max-turns 1 2>&1 | tail -2
# first run now, in the background, so this job returns
nohup /root/pe-watchman/run.sh >/dev/null 2>&1 &
echo "first watchman run started in background; summary at /root/pe-watchman/summary.md and reports/ in pe-queue"
