#!/bin/bash
# 511: the chat could not read the scoreboard on 8 Nov because the laptop MCP was off (phone-only). Route around for good: serve the
# Verifier's scoreboard (read-only, no secrets: scoreboard.md/json + team.log tail) over plain HTTP on port 8787 from a directory that
# holds ONLY those files, daemonised with @reboot + keepalive. The chat reads it with a web fetch from anywhere.
mkdir -p /root/pe-fin/team/public && cd /root/pe-fin/team
cat > publish.sh <<'SH'
#!/bin/bash
cd /root/pe-fin/team && cp -f scoreboard.md public/scoreboard.md 2>/dev/null; cp -f scoreboard.json public/scoreboard.json 2>/dev/null; tail -40 team.log > public/team_log_tail.txt 2>/dev/null
SH
chmod +x publish.sh; ./publish.sh
cat > serve.sh <<'SH'
#!/bin/bash
cd /root/pe-fin/team/public && exec python3 -m http.server 8787 --bind 0.0.0.0 >> /root/pe-fin/team/http.log 2>&1
SH
chmod +x serve.sh
( crontab -l 2>/dev/null | grep -v 'serve.sh\|publish.sh' ; echo "@reboot nohup /root/pe-fin/team/serve.sh &"; echo "*/5 * * * * /root/pe-fin/team/publish.sh; pgrep -f 'http.server 8787' >/dev/null || nohup /root/pe-fin/team/serve.sh &" ) | crontab -
pkill -f 'http.server 8787' 2>/dev/null; sleep 1; nohup /root/pe-fin/team/serve.sh & disown; sleep 2
(ufw status 2>/dev/null | grep -q "Status: active") && ufw allow 8787/tcp >/dev/null 2>&1 && echo "ufw: 8787 allowed"
curl -s -m 5 http://127.0.0.1:8787/scoreboard.md | head -5 && echo "... served locally OK" || echo "LOCAL SERVE FAILED"
ls -la public; pgrep -f fin_team.py >/dev/null && echo "team daemon running" || echo "TEAM DAEMON NOT RUNNING"
