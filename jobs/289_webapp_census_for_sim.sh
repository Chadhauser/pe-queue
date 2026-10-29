#!/bin/bash
# 289: census of the existing web app (goal-signal /positions) so the Ladder Sim can be hosted on it: framework, port, domain,
# TLS, routes, how it is started, static dir. Plus replay material available: games on the live-key stream with ESPN goals.
set -e
echo "== pe-push files"; ls -la /root/pe-push | head -40
echo "== web server processes"; pgrep -af "flask|gunicorn|uvicorn|node|nginx|caddy|http.server|app.py|server.py" | head
echo "== listening ports"; (ss -ltnp 2>/dev/null || netstat -ltnp 2>/dev/null) | head -20
echo "== nginx/caddy config"; ls /etc/nginx/sites-enabled 2>/dev/null; cat /etc/nginx/sites-enabled/* 2>/dev/null | head -60; cat /etc/caddy/Caddyfile 2>/dev/null | head -40
echo "== app entry"; for f in /root/pe-push/*.py; do echo "-- $f"; head -30 "$f" | grep -n "Flask\|FastAPI\|route\|app.run\|port\|static\|templates" ; done
echo "== systemd units"; systemctl list-units --type=service 2>/dev/null | grep -i "pe-\|push\|flask\|gunicorn" || true; ls /etc/systemd/system | grep -i "pe\|push" || true
echo "== crontab web lines"; crontab -l | grep -i "push\|app\|serve" || true
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
k=psycopg2.connect(DB,sslmode='require').cursor()
k.execute("""SELECT count(DISTINCT s.market_id) games, count(*) ticks FROM stream_ticks s WHERE s.sport='football' AND s.mkt='MO' AND s.ts_recv>'2026-10-27 09:37' AND s.back_px IS NOT NULL
             AND EXISTS (SELECT 1 FROM espn_stats e WHERE e.market_id=s.market_id)"""); print("replayable games since live key (with ESPN):",k.fetchone())
k.execute("SELECT count(*) FROM push_subscriptions"); print("push subscriptions now:",k.fetchone())
PY
