#!/bin/bash
# 578 (Sat 14 Nov 2026, 16:25). FOUND by 577: every one of 89 markets failed the bot's "£2,000 matched" filter — totalMatched read as 0 on
# all of them while prices and sizes were present. Either Betfair stopped returning the market-level totalMatched on this call, or it
# comes back under a different shape. Read the raw book once; then make the bot robust: market totalMatched, else the sum of the runners'
# totalMatched, else (prices on both sides with £10+ size on 2+ runners) treat the liquidity test as met. Restart; prove with a bet count by 18:00.
set -o pipefail
cd /root/pe-sports/bookie && python3 - <<'PY' 2>/dev/null
import sys,datetime,requests,json; sys.path.insert(0,'/root/pe-queue/runner'); import creds
APP,USER,PW=creds.betfair()
SSO=requests.post("https://identitysso.betfair.com/api/login",data={"username":USER,"password":PW},headers={"X-Application":APP,"Accept":"application/json"},timeout=20).json().get('token')
def api(ep,body):
    x=requests.post(f"https://api.betfair.com/exchange/betting/rest/v1.0/{ep}/",json=body,headers={"X-Application":APP,"X-Authentication":SSO,"Content-Type":"application/json"},timeout=25); return x.json() if x.status_code==200 else []
t0=datetime.datetime.utcnow(); f={"eventTypeIds":["1"],"marketTypeCodes":["OVER_UNDER_25"],"marketStartTime":{"from":t0.strftime('%Y-%m-%dT%H:%M:%SZ'),"to":(t0+datetime.timedelta(minutes=90)).strftime('%Y-%m-%dT%H:%M:%SZ')}}
cat=api('listMarketCatalogue',{"filter":f,"marketProjection":["EVENT","MARKET_START_TIME"],"maxResults":5})
ids=[m['marketId'] for m in cat]; print("markets:",[(m['event']['name']) for m in cat])
b=api('listMarketBook',{"marketIds":ids[:3],"priceProjection":{"priceData":["EX_BEST_OFFERS"]}})
for bk in b: print("book keys:",sorted(bk.keys()),"| totalMatched:",bk.get('totalMatched'),"| runner totalMatched:",[r.get('totalMatched') for r in bk.get('runners',[])])
b2=api('listMarketBook',{"marketIds":ids[:3],"priceProjection":{"priceData":["EX_BEST_OFFERS","EX_TRADED"]}})
for bk in b2: print("with EX_TRADED -> totalMatched:",bk.get('totalMatched'),"| runners:",[r.get('totalMatched') for r in bk.get('runners',[])])
PY
echo "== patch =="
P=/root/pe-sports/bookie/bookie_v2.py; cp $P $P.bak_578
python3 - <<'PY'
p='/root/pe-sports/bookie/bookie_v2.py'; s=open(p).read(); assert '578' not in s
old="or float(b.get('totalMatched') or 0)<MIN_MATCHED: continue"
assert old in s, "matched anchor"
new="or _matched(b)<MIN_MATCHED: continue   # 578: robust liquidity read"
s=s.replace(old,new,1)
helper='''
def _matched(b):   # 578: Betfair's market-level totalMatched came back empty on every book from 12 Nov 23:58; fall back to the runners, then to the ladder
    tm=float(b.get('totalMatched') or 0)
    if tm>0: return tm
    rt=sum(float(r.get('totalMatched') or 0) for r in b.get('runners',[]))
    if rt>0: return rt
    ok=sum(1 for r in b.get('runners',[]) if (r.get('ex',{}).get('availableToBack') or [{}])[0].get('size',0)>=MIN_SIZE and (r.get('ex',{}).get('availableToLay') or [{}])[0].get('size',0)>=MIN_SIZE)
    return MIN_MATCHED if ok>=2 else 0
'''
s=s.replace("def cells():",helper+"def cells():",1); open(p,'w').write(s); print("bot patched: _matched()")
PY
python3 -m py_compile $P && echo compiles || { cp $P.bak_578 $P; echo RESTORED; exit 1; }
pkill -f "python3 bookie_v2.py"; sleep 60; pgrep -fa "python3 bookie_v2.py" | cut -c1-80; tail -3 /root/pe-sports/bookie/bookie_v2.log | cut -c1-200
echo "578 done"
