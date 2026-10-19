#!/bin/bash
# 116: REBOOT-PROOF (Contabo kernel patch reboots 17-19 Oct). Everything must self-start: list crontab keepalives, add any missing
# (pg_bot, runner, m1, recorders), and make the Factory resume via cron (@reboot + 03:30) instead of a one-off nohup.
echo "== crontab =="; crontab -l
for want in "pe-queue/runner" "pe-liq/keepalive" "pe-ip/keepalive" "pe-xx/keepalive" "m1_keepalive" "pg_bot\|pe-pg"; do crontab -l | grep -q "$want" && echo "OK   $want" || echo "MISSING $want"; done
# factory: resume at boot if today's run has no results yet; keep nightly 03:30
cat > /root/pe-factory/resume.sh <<'SH'
#!/bin/bash
exec 8>/root/pe-factory/factory.lock; flock -n 8 || exit 0
cd /root/pe-factory && python3 - <<'PY'
import sys,datetime,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require').cursor(); c.execute("SELECT count(*) FROM strategy_results WHERE run_date=current_date"); n=c.fetchone()[0]
sys.exit(0 if n>0 else 1)
PY
[ $? -eq 0 ] && exit 0
timeout 7200 python3 factory.py >> factory.log 2>&1
SH
chmod +x /root/pe-factory/resume.sh
( crontab -l 2>/dev/null | grep -v "pe-factory" ; echo "@reboot sleep 120 && /root/pe-factory/resume.sh" ; echo "30 3 * * * /root/pe-factory/resume.sh" ; echo "0 */2 * * * /root/pe-factory/resume.sh" ) | crontab -
echo "factory: @reboot + 03:30 + 2-hourly resume if today's results missing"
pgrep -af "factory.py" || echo "factory not running now -> starting via resume.sh"; nohup /root/pe-factory/resume.sh >/dev/null 2>&1 &
echo "== factory log tail =="; tail -4 /root/pe-factory/factory_run.log 2>/dev/null; tail -4 /root/pe-factory/factory.log 2>/dev/null
echo "== pg_bot process =="; pgrep -af pg_bot.py || echo "pg_bot NOT running"
