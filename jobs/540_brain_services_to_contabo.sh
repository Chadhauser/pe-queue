#!/bin/bash
# 540 (Mon 9 Nov 2026). Railway -> Contabo, step 2: the goal-signal engine (pe-trading-brain, Railway service "python brain/monitor_ht.py")
# and its stats collector run on this box from now, against whatever database creds.pg_railway() points at (Railway until 536's cut,
# local after). Same code, same repo (Chadhauser/pe-trading-brain, main), env from creds at start-up — nothing typed by Peter. Keepalives.
# Once the local monitor is beating, the hourly sync stops pulling goal_alerts / m1_alerts / real_trades from Railway (the local monitor is
# the writer now; Railway's copy diverges until Peter cancels the project). Copilot web app, racing scanner, replay, baseline, capture
# are NOT started here: pushes are off, pe-race is STOPPED, and each is listed below for a yes/no in the header rather than guessed.
set -o pipefail
export PYTHONDONTWRITEBYTECODE=1
D=/root/pe-brain
mkdir -p $D && cd $D
if [ -d repo/.git ]; then (cd repo && git pull -q --rebase && git log -1 --format='repo at %h %ci'); else git clone -q https://github.com/Chadhauser/pe-trading-brain.git repo && (cd repo && git log -1 --format='repo at %h %ci'); fi
[ -d venv ] || python3 -m venv venv
./venv/bin/pip install -q -r repo/requirements-railway.txt && echo "deps installed"
cat > env.sh <<'SH'
#!/bin/bash
# exported fresh at every start so the services follow the database cutover automatically
eval "$(/usr/bin/python3 - <<'PY'
import sys, shlex; sys.path.insert(0,'/root/pe-queue/runner'); import creds
app,user,pw=creds.betfair()
print("export DATABASE_URL="+shlex.quote(creds.pg_railway()))
print("export APIFOOTBALL_KEY="+shlex.quote(creds.apifootball()))
print("export BETFAIR_APP_KEY="+shlex.quote(app)); print("export BETFAIR_USERNAME="+shlex.quote(user)); print("export BETFAIR_PASSWORD="+shlex.quote(pw))
PY
)"
export PYTHONPATH=/root/pe-brain/repo/brain PYTHONUNBUFFERED=1 SERVICE_NAME=contabo TG_BOT_TOKEN= TG_CHAT_ID=
SH
chmod +x env.sh
for svc in monitor_ht stats_collector; do
cat > run_$svc.sh <<SH
#!/bin/bash
cd /root/pe-brain/repo && while true; do source /root/pe-brain/env.sh; /root/pe-brain/venv/bin/python -u brain/$svc.py >> /root/pe-brain/$svc.log 2>&1; echo "\$(date -u) $svc exited \$?" >> /root/pe-brain/$svc.log; sleep 20; done
SH
chmod +x run_$svc.sh
done
( crontab -l 2>/dev/null | grep -v 'pe-brain/run_'; echo "*/5 * * * * pgrep -f 'brain/monitor_ht.py' >/dev/null || nohup /root/pe-brain/run_monitor_ht.sh >/dev/null 2>&1 &"; echo "*/5 * * * * pgrep -f 'brain/stats_collector.py' >/dev/null || nohup /root/pe-brain/run_stats_collector.sh >/dev/null 2>&1 &" ) | crontab -
nohup /root/pe-brain/run_monitor_ht.sh >/dev/null 2>&1 & disown
nohup /root/pe-brain/run_stats_collector.sh >/dev/null 2>&1 & disown
sleep 120
echo "monitor pids: $(pgrep -f 'brain/monitor_ht.py' | wc -l) | stats pids: $(pgrep -f 'brain/stats_collector.py' | wc -l)"
echo "-- monitor log tail --"; tail -8 $D/monitor_ht.log; echo "-- stats log tail --"; tail -4 $D/stats_collector.log
if pgrep -f 'brain/monitor_ht.py' >/dev/null && ! grep -qi "traceback\|error" <(tail -8 $D/monitor_ht.log); then
  ( crontab -l 2>/dev/null | grep -v 'pe-migrate/sync_railway.py'; echo "7 * * * * timeout 3000 /usr/bin/python3 /root/pe-migrate/sync_railway.py goal_alerts,m1_alerts,real_trades >> /root/pe-migrate/sync.cron.log 2>&1" ) | crontab -
  echo "local monitor is the writer of goal_alerts/m1_alerts/real_trades now; hourly sync no longer pulls those three from Railway"
else echo "monitor not healthy yet — sync left pulling everything from Railway; Watchman will show the log"; fi
echo "Railway services NOT moved (need a yes/no): copilot web app (the /positions page; pushes are off), racing_scanner (pe-race is STOPPED), replay_copilot, baseline_refresher, xg_price_capture. If none is wanted, Railway can be cancelled whole."
echo "540 done"
