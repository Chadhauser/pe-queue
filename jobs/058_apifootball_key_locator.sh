#!/bin/bash
# 058: WHERE DOES THE API-FOOTBALL KEY LIVE? The goal-signal engine is still writing live predictions (06:26 UTC today), so a
# WORKING key exists somewhere. This lists every API-Football-named variable on this server by file (names + lengths, never
# values), tests each candidate against both hosts, and looks for the engine's own config (Railway service / systemd / docker /
# pm2) to say exactly where Peter should copy the key from if none here works.
cd /root && python3 - <<'PY'
import sys, requests
sys.path.insert(0,'/root/pe-queue/runner'); import creds
print("named variables:",creds.apifootball_sources())
ks=creds.apifootball_all(); print("distinct candidate values:",len(ks))
for i,k in enumerate(ks,1):
    for h,b in (({"x-apisports-key":k},"https://v3.football.api-sports.io"),({"x-rapidapi-key":k,"x-rapidapi-host":"api-football-v1.p.rapidapi.com"},"https://api-football-v1.p.rapidapi.com/v3")):
        try:
            st=requests.get(b+"/status",headers=h,timeout=20).json(); r=st.get('response') or {}
            print(f"key#{i} len={len(k)} {b}: plan={(r.get('subscription') or {}).get('plan')} limit_day={(r.get('requests') or {}).get('limit_day')} errors={st.get('errors')}")
        except Exception as e: print(f"key#{i} {b}: error {repr(e)[:80]}")
PY
echo "--- processes that look like the goal engine:"; pgrep -af "goal|signal|engine|predict" | grep -v pgrep | head
echo "--- systemd units mentioning goal/signal:"; systemctl list-units --type=service --all 2>/dev/null | grep -iE "goal|signal|pe-" | head
echo "--- docker:"; docker ps --format '{{.Names}} {{.Image}}' 2>/dev/null | head
echo "--- pm2:"; pm2 ls 2>/dev/null | head
echo "--- files on this box that reference api-sports / rapidapi (path only):"; grep -rlE "api-sports|rapidapi|API_FOOTBALL|APIFOOTBALL" /root --include=*.py --include=*.env --include=*.sh --include=*.json --include=*.toml --include=*.yaml 2>/dev/null | grep -v pe-queue | head -20
echo "--- railway CLI present?"; which railway && railway whoami 2>&1 | head -2
