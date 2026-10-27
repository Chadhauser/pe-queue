#!/bin/bash
# 268: IS OUR APP KEY THE DELAYED ONE? The stream writes ~20 ticks/min across 8 in-play markets — a live key would give hundreds.
# Betfair issues two keys per account: live and DELAYED (data 1-180 s late, heavily conflated). Decisive checks:
#  (a) getDeveloperAppKeys -> which key has delayData=true, and which one creds.betfair() returns;
#  (b) listMarketBook -> isMarketDataDelayed on a live market;
#  (c) 30 s of raw stream messages on one busy market: count mcm messages and the pt spacing.
set -e
python3 - <<'PY'
import sys,json,time,socket,ssl,datetime,requests; sys.path.insert(0,'/root/pe-queue/runner'); import creds
app,user,pw=creds.betfair()
l=requests.post("https://identitysso.betfair.com/api/login",data={"username":user,"password":pw},headers={"X-Application":app,"Accept":"application/json"},timeout=15).json()
assert l.get('status')=='SUCCESS', "login failed "+str(l); tok=l['token']
H={"X-Authentication":tok,"X-Application":app,"Content-Type":"application/json","Accept":"application/json"}
r=requests.post("https://api.betfair.com/exchange/account/rest/v1.0/getDeveloperAppKeys/",headers=H,json={},timeout=20).json()
print("== app keys on the account")
for a in r:
    for v in a.get('appVersions',[]):
        print(f"  key ...{v['applicationKey'][-6:]}  delayData={v.get('delayData')}  active={v.get('active')}  subscriptionRequired={v.get('subscriptionRequired')}  ownerManaged={v.get('ownerManaged')}")
print("  key in use ...%s" % app[-6:])
cat=requests.post("https://api.betfair.com/exchange/betting/rest/v1.0/listMarketCatalogue/",headers=H,json={"filter":{"eventTypeIds":["1"],"marketTypeCodes":["MATCH_ODDS"],"inPlayOnly":True},"maxResults":5,"sort":"MAXIMUM_TRADED","marketProjection":["EVENT"]},timeout=20).json()
mids=[m['marketId'] for m in cat]; print("== in-play markets:",[(m['marketId'],m['event']['name']) for m in cat][:3])
if mids:
    mb=requests.post("https://api.betfair.com/exchange/betting/rest/v1.0/listMarketBook/",headers=H,json={"marketIds":mids[:1],"priceProjection":{"priceData":["EX_BEST_OFFERS"]}},timeout=20).json()
    print("== listMarketBook isMarketDataDelayed:",mb[0].get('isMarketDataDelayed'),"| status",mb[0].get('status'),"| matched",mb[0].get('totalMatched'))
    ctx=ssl.create_default_context(); s=ctx.wrap_socket(socket.create_connection(("stream-api.betfair.com",443),timeout=30),server_hostname="stream-api.betfair.com"); f=s.makefile('rb')
    def send(o): s.sendall((json.dumps(o)+"\r\n").encode())
    f.readline(); send({"op":"authentication","id":1,"appKey":app,"session":tok}); print("stream auth:",f.readline().decode().strip()[:100])
    send({"op":"marketSubscription","id":2,"marketFilter":{"marketIds":mids[:1]},"marketDataFilter":{"fields":["EX_BEST_OFFERS_DISP","EX_LTP","EX_TRADED_VOL","EX_MARKET_DEF"],"ladderLevels":3},"conflateMs":0,"heartbeatMs":5000})
    t0=time.time(); n=0; pts=[]; hb=0; s.settimeout(35)
    while time.time()-t0<30:
        try: line=f.readline()
        except socket.timeout: break
        m=json.loads(line)
        if m.get('op')!='mcm': print("  ",line.decode().strip()[:160]); continue
        if m.get('ct')=='HEARTBEAT': hb+=1; continue
        n+=1; pts.append(m['pt'])
    gaps=[(b-a)/1000 for a,b in zip(pts,pts[1:])]
    print(f"== raw stream, 1 busy market, 30 s: mcm messages {n} | heartbeats {hb} | median gap between messages {sorted(gaps)[len(gaps)//2] if gaps else None} s | min {min(gaps) if gaps else None}")
    print("   first mcm keys:", list(m.keys()) if n else None)
PY
