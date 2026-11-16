#!/bin/bash
# 614 (Mon 16 Nov 2026, 16:20). Promised 15 Nov: never again trust our own tables for real money. Hourly: read Betfair's cleared (settled)
# orders for the last 24 h; any real settled bet = BREAK in reports/breaks.md (nothing is authorised to bet real money). Plus a census of
# every file on the box that can call placeOrders, written to the report, and a hard switch file each placer must respect.
set -o pipefail
cat > /root/pe-sports/team/real_money_guard.py <<'PY'
import sys, datetime, requests, json
sys.path.insert(0,'/root/pe-queue/runner'); import creds
APP,U,P=creds.betfair()
tok=requests.post("https://identitysso.betfair.com/api/login",data={"username":U,"password":P},headers={"X-Application":APP,"Accept":"application/json"},timeout=20).json().get('token')
H={"X-Application":APP,"X-Authentication":tok,"Content-Type":"application/json"}
fr=(datetime.datetime.utcnow()-datetime.timedelta(hours=24)).strftime('%Y-%m-%dT%H:%M:%SZ')
r=requests.post("https://api.betfair.com/exchange/betting/rest/v1.0/listClearedOrders/",headers=H,json={"betStatus":"SETTLED","settledDateRange":{"from":fr},"recordCount":1000},timeout=30).json()
o=r.get('clearedOrders',[]) if isinstance(r,dict) else []
pnl=sum(float(x.get('profit',0)) for x in o)
line=f"{datetime.datetime.utcnow():%FT%H:%M} real settled bets 24h: {len(o)}, £{pnl:+.2f}"
print(line)
if o:
    with open('/root/pe-queue/reports/breaks.md','a') as f: f.write(f"{datetime.datetime.utcnow():%FT%H:%M} BREAK: REAL MONEY — {len(o)} real bets settled in 24 h (£{pnl:+.2f}); markets {sorted({x.get('marketId') for x in o})[:10]}\n")
PY
python3 /root/pe-sports/team/real_money_guard.py
( crontab -l | grep -v real_money_guard; echo "5 * * * * cd /root/pe-sports/team && /usr/bin/python3 real_money_guard.py >> real_money_guard.log 2>&1" ) | crontab - && crontab -l | grep real_money_guard
R=/root/pe-queue/reports/placeorders_census.md
{ echo "# Files that can place real bets — $(date -u '+%F %H:%M') UTC"; echo; echo "Running processes are marked RUNNING. Every placer must check /root/REAL_MONEY_OFF and refuse while it exists."; echo
  for f in $(grep -rl --include=*.py -e placeOrders -e place_orders /root/pe-* /root/operators 2>/dev/null | grep -v -e '\.bak' -e __pycache__); do
    b=$(basename $f); run=$(pgrep -fa "$b" >/dev/null && echo RUNNING || echo stopped); guard=$(grep -q REAL_MONEY_OFF $f && echo "has switch" || echo "NO switch"); echo "- $f — $run — $guard"; done; } > $R
touch /root/REAL_MONEY_OFF
cat $R | head -40
cd /root/pe-queue && git add reports/placeorders_census.md reports/breaks.md 2>/dev/null; git commit -qm "614: real-money guard + placer census" ; git pull -q --no-rebase --no-edit; git push -q
echo "614 done"
