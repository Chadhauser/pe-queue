#!/bin/bash
# 512: read route that needs neither the laptop nor an open port: the Verifier's scoreboard is committed to THIS repo under
# scoreboard/ every 5 minutes by publish.sh, using GH_SCOREBOARD_TOKEN from /root/pe-logger/.env (fine-grained, pe-queue only,
# contents read/write). No secret in the repo; the token stays on the box. Idempotent: does nothing until the token exists.
cd /root/pe-fin/team || exit 1
TOK=$(python3 -c "import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds; print(creds.all_vars().get('GH_SCOREBOARD_TOKEN',''))")
[ -n "$TOK" ] || { echo "GH_SCOREBOARD_TOKEN not set yet — nothing to do (re-run 512 after the paste)"; exit 0; }
cat > publish.sh <<'SH'
#!/bin/bash
cd /root/pe-fin/team && cp -f scoreboard.md public/scoreboard.md 2>/dev/null; cp -f scoreboard.json public/scoreboard.json 2>/dev/null; tail -40 team.log > public/team_log_tail.txt 2>/dev/null
TOK=$(python3 -c "import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds; print(creds.all_vars().get('GH_SCOREBOARD_TOKEN',''))"); [ -n "$TOK" ] || exit 0
W=/root/pe-fin/team/repo
if [ ! -d $W/.git ]; then git clone -q --depth 1 "https://x-access-token:${TOK}@github.com/Chadhauser/pe-queue.git" $W 2>/dev/null || exit 0; git -C $W config user.email fin-team@server; git -C $W config user.name "fin-team"; fi
cd $W && git pull -q --rebase 2>/dev/null; mkdir -p scoreboard && cp -f /root/pe-fin/team/public/* scoreboard/ && git add scoreboard && git -c commit.gpgsign=false commit -qm "scoreboard $(date -u +%Y-%m-%dT%H:%M)" 2>/dev/null && git push -q 2>/dev/null
SH
chmod +x publish.sh && ./publish.sh && echo "pushed:" && git -C /root/pe-fin/team/repo log --oneline -1 | sed 's/^/  /'
