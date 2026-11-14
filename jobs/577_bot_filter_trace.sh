#!/bin/bash
# 577 (Sat 14 Nov 2026, 15:20). 576: the bot's Betfair calls work (login ok, 120 markets in the window, books with prices) and its loop
# runs to the heartbeat every pass — it just finds nothing to take. So one of its filters now rejects everything. Print the loop and trace
# each filter against the live books: how many runners survive time-to-off, min matched, min size, max price, band, side.
set -o pipefail
echo "== bookie_v2.py lines 36-110 =="; sed -n 36,110p /root/pe-sports/bookie/bookie_v2.py | cut -c1-260
echo "== trace =="
cd /root/pe-sports/bookie && python3 - <<'PY' 2>/dev/null
import sys,time,datetime,requests,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
APP,USER,PW=creds.betfair()
SSO=requests.post("https://identitysso.betfair.com/api/login",data={"username":USER,"password":PW},headers={"X-Application":APP,"Accept":"application/json"},timeout=20).json().get('token')
def api(ep,body):
    x=requests.post(f"https://api.betfair.com/exchange/betting/rest/v1.0/{ep}/",json=body,headers={"X-Application":APP,"X-Authentication":SSO,"Content-Type":"application/json"},timeout=25); return x.json() if x.status_code==200 else []
c=psycopg2.connect(creds.pg_local(),sslmode='disable').cursor()
c.execute("select column_name from information_schema.columns where table_name='fair_price_passed'"); print("fair_price_passed columns:",[r[0] for r in c.fetchall()])
c.execute("SELECT * FROM fair_price_passed LIMIT 3"); print("sample rows:",c.fetchall())
c.execute("SELECT market_type, band_lo, band_hi, side, fair_factor FROM fair_price_passed"); C={}
for mt,lo,hi,side,f in c.fetchall(): C.setdefault(mt,[]).append((float(lo),float(hi),side,float(f)))
t0=datetime.datetime.utcnow(); f={"eventTypeIds":["1"],"marketTypeCodes":sorted(C),"marketStartTime":{"from":(t0-datetime.timedelta(minutes=5)).strftime('%Y-%m-%dT%H:%M:%SZ'),"to":(t0+datetime.timedelta(minutes=60)).strftime('%Y-%m-%dT%H:%M:%SZ')}}
cat={m['marketId']:m for m in api('listMarketCatalogue',{"filter":f,"marketProjection":["EVENT","MARKET_START_TIME","MARKET_DESCRIPTION"],"maxResults":200})}
print("markets:",len(cat))
ids=list(cat)[:120]; books=[]
for i in range(0,len(ids),40): books+=api('listMarketBook',{"marketIds":ids[i:i+40],"priceProjection":{"priceData":["EX_BEST_OFFERS"]}})
n=dict(runners=0,prices=0,matched=0,size=0,price=0,inband=0,window=0); ex=[]
for b in books:
    m=cat.get(b['marketId']); mt=(m.get('description') or {}).get('marketType'); 
    sto=(datetime.datetime.strptime(m['marketStartTime'],'%Y-%m-%dT%H:%M:%S.%fZ')-t0).total_seconds()
    for rn in b.get('runners',[]):
        n['runners']+=1
        ab=rn.get('ex',{}).get('availableToBack') or []; al=rn.get('ex',{}).get('availableToLay') or []
        if not ab or not al: continue
        n['prices']+=1
        if (b.get('totalMatched') or 0)<2000: continue
        n['matched']+=1
        bb,bs,bl,ls=ab[0]['price'],ab[0]['size'],al[0]['price'],al[0]['size']
        if bs<10 or ls<10: continue
        n['size']+=1
        if bl>20: continue
        n['price']+=1
        p=1/((bb+bl)/2)
        hit=[(lo,hi,side) for lo,hi,side,ff in C.get(mt,[]) if lo<=p<hi]
        if not hit: continue
        n['inband']+=1; ex.append((m['event']['name'],mt,round(p,3),hit[0][2],round(sto/60,1)))
        if 0<sto<=120: n['window']+=1
print("filter survivors:",n)
print("in-band examples (event, type, p, side, minutes to off):",ex[:12])
print("so: in-band runners exist" if n['inband'] else "so: NO runner falls inside any passed band -> the bands or the probability used no longer meet")
PY
echo "577 done"
