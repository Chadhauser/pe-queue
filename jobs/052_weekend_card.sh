#!/bin/bash
# 052: THE WEEKEND CARD — Peter's manual plan, produced automatically every Friday 17:00 London (cron) and once now.
# Pulls every football MATCH_ODDS market kicking off Sat/Sun (or next 3 days) from the Betfair catalogue, ranks by money
# already matched, and writes the 8 deepest games with KO time, prices and the manual procedure (M1 post-goal fade at size)
# to /root/pe-report/weekend.txt. Nothing to decide on the day: the games, the size and the rules are on the card.
mkdir -p /root/pe-report && cat > /root/pe-report/weekend_card.py <<'PYFILE'
import sys, datetime, requests, psycopg2
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
sys.path.insert(0,'/root/pe-queue/runner'); import creds
APP_KEY,USER,PW=creds.betfair()
r=requests.post("https://identitysso.betfair.com/api/login",data={"username":USER,"password":PW},headers={"X-Application":APP_KEY,"Accept":"application/json"},timeout=15).json()
TOK=r['token']
def api(ep,p):
    return requests.post(f"https://api.betfair.com/exchange/betting/rest/v1.0/{ep}/",json=p,headers={"X-Authentication":TOK,"X-Application":APP_KEY,"Content-Type":"application/json"},timeout=20).json()
now=datetime.datetime.now(datetime.timezone.utc)
# window: coming Sat 00:00 -> Sun 23:59 UK; if today is Sat/Sun use today -> Sun
wd=now.weekday(); start=now if wd>=5 else now+datetime.timedelta(days=(5-wd))
start=start.replace(hour=0,minute=0,second=0,microsecond=0); end=start+datetime.timedelta(days=(2 if wd<6 else 1))
res=api('listMarketCatalogue',{"filter":{"eventTypeIds":["1"],"marketTypeCodes":["MATCH_ODDS"],"marketStartTime":{"from":start.isoformat().replace('+00:00','Z'),"to":end.isoformat().replace('+00:00','Z')}},
        "marketProjection":["EVENT","COMPETITION","RUNNER_DESCRIPTION","MARKET_START_TIME"],"sort":"MAXIMUM_TRADED","maxResults":60})
ids=[m['marketId'] for m in res]
books={}
for i in range(0,len(ids),20):
    for b in api('listMarketBook',{"marketIds":ids[i:i+20],"priceProjection":{"priceData":["EX_BEST_OFFERS"]}}): books[b['marketId']]=b
rows=[]
for m in res:
    b=books.get(m['marketId'],{}); tm=b.get('totalMatched') or 0
    px={}
    for rn in b.get('runners',[]):
        name=next((x['runnerName'] for x in m['runners'] if x['selectionId']==rn['selectionId']),'?')
        bb=rn.get('ex',{}).get('availableToBack',[]); px[name]=bb[0]['price'] if bb else None
    ko=datetime.datetime.fromisoformat(m['marketStartTime'].replace('Z','+00:00')).astimezone(datetime.timezone(datetime.timedelta(hours=1)))
    rows.append((tm,ko,m['event']['name'],(m.get('competition') or {}).get('name',''),px))
rows.sort(key=lambda x:-x[0])
try:
    con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor()
    cur.execute("SELECT count(*), round(coalesce(sum(pnl),0)::numeric,2) FROM pg_trades WHERE status='CLOSED' AND opened_at>=now()-interval '7 days'"); n,p=cur.fetchone()
    botline=f"Bot (PG v3) last 7 days: {n} trades, £{p}"
except Exception as e: botline="Bot line unavailable: "+repr(e)[:60]
L=[f"WEEKEND CARD — produced {now.astimezone(datetime.timezone(datetime.timedelta(hours=1))):%a %d %b %H:%M} UK — {botline}",
   "", "MANUAL PROCEDURE M1 (post-goal fade at size — the only football edge that has passed out-of-sample so far):",
   "  Games: the 8 below (deepest money). Watch BBC/FotMob for goals; be on the Match Odds ladder.",
   "  Trigger: a goal between 10' and 75' that takes the SCORING team's price to 1.30–2.50 (not the 3rd+ goal, not after a red card).",
   "  Entry: 60 seconds after the market reopens, LAY the scoring team at best lay. Stake £10 this weekend (bank gate: double after each positive fortnight).",
   "  Exit: BACK the same team 10 minutes later at best back, or immediately on the next suspension (another goal/red) whichever first. No holding, no opinions.",
   "  Record each: Match | goal min | entry lay | exit back | P&L — post the five lines to Claude on Sunday. 3–4 trades is the whole job; more is not better.",
   "", f"{'KO (UK)':9s} {'matched £':>10s}  {'match':40s} {'competition':28s} prices (H / D / A)"]
for tm,ko,ev,comp,px in rows[:8]:
    names=list(px.keys()); h=names[0] if names else '?'; a=next((x for x in names if x!=h and x!='The Draw'),'?')
    L.append(f"{ko:%a %H:%M}  {tm:>10,.0f}  {ev[:40]:40s} {comp[:28]:28s} {px.get(h)} / {px.get('The Draw')} / {px.get(a)}")
L.append(""); L.append("Next 12 by money (reserve, only if a top-8 game is a dead rubber or already 2-0 before 10'):")
for tm,ko,ev,comp,px in rows[8:20]: L.append(f"  {ko:%a %H:%M}  {tm:>10,.0f}  {ev[:40]} ({comp[:24]})")
open('/root/pe-report/weekend.txt','w').write("\n".join(L)); print("\n".join(L))
PYFILE
python3 -m py_compile /root/pe-report/weekend_card.py || exit 1
( crontab -l 2>/dev/null | grep -v weekend_card ; echo "CRON_TZ=Europe/London" ; echo "0 17 * * 5 cd /root/pe-report && python3 weekend_card.py >> weekend_card.log 2>&1" ) | crontab -
python3 /root/pe-report/weekend_card.py
