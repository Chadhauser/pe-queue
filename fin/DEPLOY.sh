#!/bin/bash
# FIN DEPLOY — run ONCE, only after reports/post_upgrade.md shows the Storage VPS 30 upgrade is done (Peter's order 16 Nov 14:54).
# Sets up the segregated fin runner + the Alpaca PAPER bot tick. Starts nothing else: no team loop, no data pulls, no Wine/MT5.
# Refuses to run if the upgrade report is missing or free disk is under 25 GB. Idempotent. Report -> fin/reports/deploy.txt
unset GITHUB_TOKEN
set -u
S=/root/pe-finq/state; R=/root/pe-finq/repo; mkdir -p $S
OUT=$S/deploy.txt; : > $OUT; say(){ echo "$(date -u +%H:%M:%S) $*" | tee -a $OUT; }
[ -f /root/pe-queue/reports/post_upgrade.md ] || { say "REFUSED: reports/post_upgrade.md not present yet"; exit 1; }
G=$(df -BG --output=avail / | tail -1 | tr -dc 0-9); [ "$G" -ge 25 ] || { say "REFUSED: only ${G} GB free"; exit 1; }
say "disk free ${G} GB | memory $(free -g | awk '/Mem:/{print $2}') GB | cores $(nproc)"
# 1. own clone of the queue repo (never the shared runner's checkout)
TOK=$(python3 -c "import sys;sys.path.insert(0,'/root/pe-queue/runner');import creds;print(creds.all_vars().get('GH_SCOREBOARD_TOKEN',''))")
[ -d $R/.git ] || git clone -q --depth 20 https://github.com/Chadhauser/pe-queue.git $R || { say "FAIL: clone"; exit 1; }
cd $R && git remote set-url origin "https://x-access-token:${TOK}@github.com/Chadhauser/pe-queue.git" && git config user.name "pe-fin-runner" && git config user.email "fin-runner@localhost"
git pull -q --rebase origin main; say "own clone at $R, head $(git rev-parse --short HEAD)"
chmod +x $R/fin/runner/fin_runner.sh
# 2. offline test on the box (fake broker, no network) — must be 19/19
cd $R/fin/bots && T=$(timeout 300 python3 test_tick.py 2>&1 | tail -1); say "offline bot test: $T"
echo "$T" | grep -qE "^([0-9]+)/\1 PASS$" || { say "FAIL: offline test did not pass — not deploying"; exit 1; }
# 3. paper account reachable (paper endpoint only)
say "$(cd $R/fin/bots && timeout 60 python3 tick.py --check 2>&1 | tail -1)"
# 4. make sure no old fin bot is still scheduled or running (the old long-running bots are replaced by the tick)
pkill -f orb_alpaca_bot.py; pkill -f k2_gapfade_bot.py; pkill -f k4_reversal_bot.py
crontab -l > /root/crontab_before_finq_$(date +%Y%m%d%H%M).txt 2>/dev/null
( crontab -l 2>/dev/null | grep -v '# FINQ'
  echo "*/2 * * * * nice -n 19 ionice -c3 $R/fin/runner/fin_runner.sh >> $S/runner.out 2>&1 # FINQ"
  echo "* * * * * cd $R/fin/bots && nice -n 19 ionice -c3 timeout 300 /usr/bin/python3 tick.py >> $S/tick.out 2>&1 # FINQ" ) | crontab -
say "cron: $(crontab -l | grep -c '# FINQ') FINQ lines (runner every 2 min, bot tick every minute) | old fin cron lines: $(crontab -l | grep -cE '/root/pe-fin/|mt5')"
say "wine on box: $(command -v wine || echo none)"
mkdir -p $R/fin/reports && cp $OUT $R/fin/reports/deploy.txt && cd $R && git add fin/reports/deploy.txt && git commit -qm "fin deploy report" && git pull -q --rebase origin main && git push -q origin HEAD:main
say "DONE fin deploy"
