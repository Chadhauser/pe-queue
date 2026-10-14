#!/bin/bash
# 059: install the API-Football key Peter supplied (14 Oct, from Railway glorious-dream APIFOOTBALL_KEY) via the encrypted transfer
# channel, then verify it against both hosts. Job 014 (waiting) picks it up on the next cycle and starts the red-card backfill.
KEY=$(grep -E '^TRANSFER_KEY=' /root/pe-logger/.env | cut -d= -f2- | tr -d '"\047 \015' | grep -E '^[0-9a-f]{32}$' | tail -1)
[ -z "$KEY" ] && { echo "no TRANSFER_KEY"; exit 1; }
RAW=https://raw.githubusercontent.com/Chadhauser/pe-transfer/main; mkdir -p /root/transfer
curl -fsSL "$RAW/apifootball.env.enc" -o /root/transfer/apifootball.env.enc && curl -fsSL "$RAW/apifootball.env.md5" -o /root/transfer/apifootball.env.md5
openssl enc -d -aes-256-cbc -pbkdf2 -in /root/transfer/apifootball.env.enc -out /root/transfer/apifootball.env -pass pass:"$KEY" || { echo DECRYPT FAILED; exit 1; }
[ "$(md5sum /root/transfer/apifootball.env | cut -d' ' -f1)" = "$(cat /root/transfer/apifootball.env.md5)" ] || { echo MD5 MISMATCH; exit 1; }
# remove any older API-Football lines so the new key is the one creds.py finds first
sed -i -E '/^(API_FOOTBALL_KEY|APIFOOTBALL_KEY|APISPORTS_KEY|API_SPORTS_KEY)=/d' /root/pe-logger/.env
cat /root/transfer/apifootball.env >> /root/pe-logger/.env; rm -f /root/transfer/apifootball.env
echo "installed; key length $(grep -E '^API_FOOTBALL_KEY=' /root/pe-logger/.env | cut -d= -f2 | tr -d '\r' | wc -c)"
python3 - <<'PY'
import sys, requests; sys.path.insert(0,'/root/pe-queue/runner'); import creds
print(creds.report())
for k in creds.apifootball_all():
    for h,b in (({"x-apisports-key":k},"https://v3.football.api-sports.io"),({"x-rapidapi-key":k,"x-rapidapi-host":"api-football-v1.p.rapidapi.com"},"https://api-football-v1.p.rapidapi.com/v3")):
        try:
            st=requests.get(b+"/status",headers=h,timeout=20).json(); r=st.get('response') or {}
            print(f"len={len(k)} {b}: plan={(r.get('subscription') or {}).get('plan')} active={(r.get('subscription') or {}).get('active')} used/limit={(r.get('requests') or {}).get('current')}/{(r.get('requests') or {}).get('limit_day')} errors={st.get('errors')}")
        except Exception as e: print(b,"error",repr(e)[:80])
PY
