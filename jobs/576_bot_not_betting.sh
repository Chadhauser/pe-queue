#!/bin/bash
# 576 (Sat 14 Nov 2026, 15:05). THE REAL BREAK: 148 match-odds markets on the tape this afternoon and the bot has written no paper bet
# since Thursday 23:58. It reads its cells (logged) but its scan/placing path is silent — it only logs when it bets. Read everything:
# the lines in its log that are NOT "passed cells" (24 h), its stdout/stderr file, and run its exact catalogue call live from here.
set -o pipefail
L=/root/pe-sports/bookie/bookie_v2.log; O=/root/pe-sports/bookie/bookie_v2.out
echo "== log lines other than 'passed cells', last 24 h =="; awk -v s="$(date -u -d '-24 hours' '+%Y-%m-%d %H:%M')" '$1 ~ /^20[0-9][0-9]-/ {keep=($1" "$2>=s)} keep' $L | grep -v "passed cells" | tail -30 | cut -c1-240
echo "== stdout/stderr file tail =="; tail -30 $O 2>/dev/null | cut -c1-240
echo "== bookie_v2.py: universe filter and horizon =="; grep -n "HORIZON_MIN=\|eventTypeIds\|bf_chunk\|import" /root/pe-sports/bookie/bookie_v2.py | head -12 | cut -c1-200
echo "== live: the bot's own catalogue call =="
cd /root/pe-sports/bookie && python3 - <<'PY'
import sys,time,datetime,requests,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
APP,USER,PW=creds.betfair()
r=requests.post("https://identitysso.betfair.com/api/login",data={"username":USER,"password":PW},headers={"X-Application":APP,"Accept":"application/json"},timeout=20).json()
print("login:",r.get('status'),r.get('error'))
SSO=r.get('token')
def api(ep,body):
    x=requests.post(f"https://api.betfair.com/exchange/betting/rest/v1.0/{ep}/",json=body,headers={"X-Application":APP,"X-Authentication":SSO,"Content-Type":"application/json"},timeout=25)
    print(ep,"status",x.status_code, x.text[:160] if x.status_code!=200 else "")
    return x.json() if x.status_code==200 else []
c=psycopg2.connect(creds.pg_local(),sslmode='disable').cursor(); c.execute("SELECT distinct market_type FROM fair_price_passed"); types=sorted(t for (t,) in c.fetchall()); print("passed types:",types)
t0=datetime.datetime.utcnow(); f={"eventTypeIds":["1"],"marketTypeCodes":types,"marketStartTime":{"from":t0.strftime('%Y-%m-%dT%H:%M:%SZ'),"to":(t0+datetime.timedelta(minutes=60)).strftime('%Y-%m-%dT%H:%M:%SZ')}}
cat=api('listMarketCatalogue',{"filter":f,"marketProjection":["EVENT","MARKET_START_TIME","MARKET_DESCRIPTION"],"maxResults":200})
print("catalogue markets next 60 min:",len(cat)); print([ (m.get('marketName'), (m.get('event') or {}).get('name'), m.get('marketStartTime')) for m in cat[:5]])
if cat:
    ids=[m['marketId'] for m in cat[:40]]
    books=api('listMarketBook',{"marketIds":ids,"priceProjection":{"priceData":["EX_BEST_OFFERS"]}})
    print("books:",len(books), "runners with prices:", sum(1 for b in books for rn in b.get('runners',[]) if rn.get('ex',{}).get('availableToBack')))
f2=dict(f); f2.pop('marketStartTime'); f2["inPlayOnly"]=False
print("without the time window, maxResults 1000:", len(api('listMarketCatalogue',{"filter":f2,"maxResults":1000})))
try:
    sys.path.insert(0,'/root/pe-liq'); import bf_chunk; print("bf_chunk shim importable:", bf_chunk.__file__)
except Exception as e: print("bf_chunk:",e)
c.execute("select id,last_seen,open_orders,fills from bookie_heartbeat order by id"); print("heartbeat rows:",c.fetchall())
c.execute("select max(ts), count(*) filter (where ts>now()-interval '48 hours') from bookie_paper where version='v2'"); print("bookie_paper last / 48h:",c.fetchone())
PY
echo "576 done"
