#!/bin/bash
# 072: BETFAIR_USERNAME / BETFAIR_PASSWORD vanished from /root/pe-logger/.env between 10:38 and 10:55 UTC today (014 saw them,
# 065 did not) — almost certainly the Smarkets/Matchbook paste rewrote the file with '>' instead of '>>'. The live recorders and
# bots still hold the values in memory, so nothing is down YET, but any restart fails to log in. Look for a copy anywhere on this
# server and restore it; otherwise print exactly what Peter must paste. Also: 014's "rejected" message was wrong — the key works,
# the DAILY QUOTA is used up (the goal engine on Railway shares it); 014 now says so and waits for the reset.
set +e
ENV=/root/pe-logger/.env
echo "--- current .env var names:"; grep -oE '^[A-Za-z_]+' $ENV | sort -u | tr '\n' ' '; echo
echo "--- backups / history:"; ls -la /root/pe-logger/.env* /root/pe-logger/*.bak 2>/dev/null; (cd /root/pe-logger && git log --oneline -3 -- .env 2>/dev/null)
FOUND=""
for f in /root/pe-logger/.env.bak /root/pe-logger/.env~ /root/pe-logger/.env.orig /root/operators/.env /root/shopreconcile/.env /root/.env /root/pe-bot/.env /root/pe-prematch/.env /etc/environment /root/.bashrc /root/.profile; do
  [ -f "$f" ] || continue
  if grep -qE '^(export )?BETFAIR_USERNAME=' "$f" && grep -qE '^(export )?BETFAIR_PASSWORD=' "$f"; then FOUND="$f"; echo "found BETFAIR_USERNAME/PASSWORD in $f"; break; fi
done
if [ -z "$FOUND" ]; then
  echo "--- searching python files for a hard-coded username (names only):"; grep -rlE 'BETFAIR_USERNAME|betfair_username|USERNAME *= *"' /root/pe-logger /root/pe-bot /root/pe-prematch /root/pe-tennis 2>/dev/null | head
fi
if [ -n "$FOUND" ]; then
  grep -E '^(export )?BETFAIR_(USERNAME|PASSWORD)=' "$FOUND" | sed 's/^export //' >> $ENV
  echo "restored into $ENV"
fi
# also keep a dated backup of .env from now on so a bad paste is recoverable
cp $ENV /root/pe-logger/.env.$(date +%Y%m%d%H%M).bak; ls /root/pe-logger/.env.*.bak | head -3
python3 - <<'PY'
import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds, requests
a,u,p=creds.betfair(); print("creds.report:",creds.report())
if a and u and p:
    r=requests.post("https://identitysso.betfair.com/api/login",data={"username":u,"password":p},headers={"X-Application":a,"Accept":"application/json"},timeout=15).json()
    print("Betfair login test:",r.get('status'),r.get('error'))
else:
    print("STILL MISSING. Peter must paste (note the DOUBLE >> so nothing else is overwritten):")
    print('  echo "BETFAIR_USERNAME=your_betfair_username" >> /root/pe-logger/.env')
    print('  echo "BETFAIR_PASSWORD=your_betfair_password" >> /root/pe-logger/.env')
PY
# 014 message fix: quota exhausted is not a rejected key
python3 - <<'PY'
p='/root/pe-scan/events_backfill.py'
try:
    s=open(p).read()
    s=s.replace('''if not plan: print("WAITING: key rejected by BOTH api-sports.io and RapidAPI.''','''if not plan and any('rateLimit' in str(c) for c in []): pass
if not plan: print("WAITING: no plan returned - either the key is rejected or today's API-Football daily quota (7,500, shared with the Railway goal engine) is used up; retrying until the daily reset.''')
    open(p,'w').write(s); print("014 message updated")
except Exception as e: print("014 patch skipped",e)
PY
