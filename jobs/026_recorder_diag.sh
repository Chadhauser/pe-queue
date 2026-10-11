#!/bin/bash
# 026: the liquidity recorder stopped writing at 08:04 Sat 10 Oct (last liq_sample) and missed the whole Saturday programme.
# Diagnose: is it running, what did it log, is the keepalive cron there; then hard-restart it.
echo "== processes =="; pgrep -af liq_recorder.py || echo "NOT RUNNING"
echo "== crontab keepalive =="; crontab -l | grep pe-liq || echo "NO KEEPALIVE LINE"
echo "== lock =="; ls -la /root/pe-liq/; fuser /root/pe-liq/recorder.lock 2>&1 || true
echo "== recorder.log tail (errors) =="; grep -n "error\|Error\|Traceback\|SystemExit\|LOGIN" /root/pe-liq/recorder.log | tail -15
echo "== recorder.log last 25 lines =="; tail -25 /root/pe-liq/recorder.log
echo "== keepalive test run (15s) =="; pkill -f liq_recorder.py; sleep 1
timeout 15 bash /root/pe-liq/keepalive.sh; echo "keepalive rc=$?"; tail -5 /root/pe-liq/recorder.log
echo "== restart via keepalive in background =="; nohup bash /root/pe-liq/keepalive.sh >/dev/null 2>&1 &
sleep 20; pgrep -af liq_recorder.py || echo "STILL NOT RUNNING"; tail -3 /root/pe-liq/recorder.log
