#!/bin/bash
# 269: if the key in use is the DELAYED one and the account holds an ACTIVE live key that works, switch every bot to the live key.
# Guarded: the live key is tested first (login + listMarketBook must succeed with isMarketDataDelayed=false); only then is the
# delayed key value replaced in every config file on the server that holds it (no values printed), and all recorders/bots
# restarted through their keepalives. No-op with a clear message if already live, or if no working live key exists.
set -e
python3 - <<'PY'
import sys,os,re,json,subprocess,requests; sys.path.insert(0,'/root/pe-queue/runner'); import creds
app,user,pw=creds.betfair()
def login(key):
    r=requests.post("https://identitysso.betfair.com/api/login",data={"username":user,"password":pw},headers={"X-Application":key,"Accept":"application/json"},timeout=15).json()
    return r.get('token') if r.get('status')=='SUCCESS' else None
tok=login(app); assert tok, "login failed with key in use"
H=lambda k,t:{"X-Authentication":t,"X-Application":k,"Content-Type":"application/json","Accept":"application/json"}
keys=requests.post("https://api.betfair.com/exchange/account/rest/v1.0/getDeveloperAppKeys/",headers=H(app,tok),json={},timeout=20).json()
versions=[v for a in keys for v in a.get('appVersions',[])]
inuse=[v for v in versions if v['applicationKey']==app]
print("keys:",[(v['applicationKey'][-5:],'delayed' if v.get('delayData') else 'LIVE','active' if v.get('active') else 'inactive') for v in versions],"| in use ...%s"%app[-5:])
if not inuse: print("key in use not found among account keys — leaving as is"); sys.exit(0)
if not inuse[0].get('delayData'): print("ALREADY LIVE: key in use has delayData=false. The low tick rate is not the key."); sys.exit(0)
live=[v for v in versions if not v.get('delayData') and v.get('active')]
if not live: print("DELAYED key in use and NO active live key on the account — activation needed on the Betfair developer page"); sys.exit(0)
lk=live[0]['applicationKey']
# test the live key end to end
t2=login(lk)
if not t2: print("live key login failed — not switching"); sys.exit(0)
cat=requests.post("https://api.betfair.com/exchange/betting/rest/v1.0/listMarketCatalogue/",headers=H(lk,t2),json={"filter":{"eventTypeIds":["1","7"]},"maxResults":1,"sort":"MAXIMUM_TRADED"},timeout=20).json()
mb=requests.post("https://api.betfair.com/exchange/betting/rest/v1.0/listMarketBook/",headers=H(lk,t2),json={"marketIds":[cat[0]['marketId']],"priceProjection":{"priceData":["EX_BEST_OFFERS"]}},timeout=20)
ok=mb.status_code==200 and isinstance(mb.json(),list) and mb.json() and mb.json()[0].get('isMarketDataDelayed') is False
print("live key test: http",mb.status_code,"isMarketDataDelayed=",(mb.json()[0].get('isMarketDataDelayed') if ok or mb.status_code==200 else mb.text[:120]))
if not ok: print("live key does not return undelayed data — not switching"); sys.exit(0)
# replace in every config file that holds the delayed key
files=subprocess.run(["bash","-c",f"grep -rlF -- '{app}' /root/pe-* /root/.bashrc /root/.profile /etc/environment 2>/dev/null | grep -v -E '\\.git/|\\.log$|__pycache__|/pe-queue/'"],capture_output=True,text=True).stdout.split()
for f in files:
    s=open(f).read(); open(f,'w').write(s.replace(app,lk))
print("switched to LIVE key in",len(files),"files:",files)
open('/root/pe-queue-state/APP_KEY_SWITCHED','w').write('live\n')
PY
if [ -f /root/pe-queue-state/APP_KEY_SWITCHED ] && [ ! -f /root/pe-queue-state/APP_KEY_SWITCHED.done ]; then
  for p in stream_client.py liq_recorder.py xx_recorder.py stats_recorder.py espn_recorder.py xg_paper.py late_over_paper.py s9_paper.py ltd_paper.py race_mm_stream.py; do pkill -f "$p" || true; done
  sleep 3
  for k in /root/pe-stream/keepalive.sh /root/pe-liq/keepalive.sh /root/pe-xx/keepalive.sh /root/pe-stats/keepalive.sh /root/pe-stats/keepalive_espn.sh /root/pe-xg/keepalive.sh /root/pe-xg/keepalive_lo.sh /root/pe-xg/keepalive_s9.sh /root/pe-race/keepalive_mm_stream.sh; do [ -x "$k" ] && nohup "$k" >/dev/null 2>&1 & done
  sleep 90; touch /root/pe-queue-state/APP_KEY_SWITCHED.done
  python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
k=psycopg2.connect(DB,sslmode='require').cursor()
k.execute("SELECT * FROM stream_heartbeat"); print("stream hb after switch:",k.fetchall())
k.execute("SELECT count(*) FROM stream_ticks WHERE ts_recv>now()-interval '1 minute'"); print("stream ticks last minute:",k.fetchone())
k.execute("SELECT * FROM liq_heartbeat"); print("liq hb:",k.fetchall())
PY
fi
