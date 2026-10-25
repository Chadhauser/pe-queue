#!/bin/bash
# 186: two feeds look wrong at 12:10 UTC Sunday: stats heartbeat shows live=0 and 'remaining' frozen at 7499 for 40 min (no successful
# API calls?); racing tape has no rows and no heartbeat movement although UK Sunday racing should be near. Print the evidence.
echo "== stats recorder"; pgrep -af stats_recorder.py | head -2; tail -25 /root/pe-stats/stats.log
python3 - <<'PY'
import sys, requests; sys.path.insert(0,'/root/pe-queue/runner'); import creds
key=None
try:
    import os
    for line in open('/root/pe-logger/.env'):
        if line.startswith('API_FOOTBALL_KEY='): key=line.strip().split('=',1)[1]
except Exception as e: print("env read:",e)
r=requests.get("https://v3.football.api-sports.io/fixtures",params={"live":"all"},headers={"x-apisports-key":key or ''},timeout=20)
print("direct call status",r.status_code,"| remaining header",r.headers.get('x-ratelimit-requests-remaining'),"| limit",r.headers.get('x-ratelimit-requests-limit'))
j=r.json(); print("errors:",j.get('errors'),"| results:",j.get('results'))
for f in (j.get('response') or [])[:8]: print("  live:",f['league']['name'],'-',f['teams']['home']['name'],'v',f['teams']['away']['name'],f['fixture']['status'].get('elapsed'))
PY
grep -n "BASE=\|AFH=\|x-apisports-key\|x-rapidapi" /root/pe-stats/stats_recorder.py | head -5
echo "== racing"; pgrep -af race_swing.py | head -2; tail -15 /root/pe-race/race.log
python3 - <<'PY'
import sys, datetime, requests; sys.path.insert(0,'/root/pe-queue/runner'); import creds
APP,USER,PW=creds.betfair()
r=requests.post("https://identitysso.betfair.com/api/login",data={"username":USER,"password":PW},headers={"X-Application":APP,"Accept":"application/json"},timeout=15).json(); print("login:",r.get('status'))
tok=r['token']; now=datetime.datetime.now(datetime.timezone.utc)
cat=requests.post("https://api.betfair.com/exchange/betting/rest/v1.0/listMarketCatalogue/",json={"filter":{"eventTypeIds":["7"],"marketCountries":["GB","IE"],"marketTypeCodes":["WIN"],"marketStartTime":{"from":now.isoformat(),"to":(now+datetime.timedelta(hours=3)).isoformat()}},"marketProjection":["EVENT","MARKET_START_TIME"],"maxResults":50,"sort":"FIRST_TO_START"},headers={"X-Authentication":tok,"X-Application":APP,"Content-Type":"application/json"},timeout=20).json()
print("GB/IE WIN markets next 3h:",len(cat)); [print("  ",m['event']['venue'] if 'venue' in m['event'] else m['event']['name'],m['marketStartTime']) for m in cat[:8]]
PY
