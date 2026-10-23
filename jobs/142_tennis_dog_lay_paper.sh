#!/bin/bash
# 142: TENNIS OUTSIDER LAY — PAPER (Factory 23 Oct survivor, pure settle: lay the player priced 3.0-5.0 at the off +7.5 per £100
# n 12,701 (t 2.1/5.2); 5.0-10.0 +13.5 per £100 n 5,261 (t 2.3/3.8); Aug 2024 -> Mar 2026). Paper bot: every 60s, tennis MATCH_ODDS
# starting in 1-4 minutes; record both runners' back/lay at that moment (tennis_dog_tape); paper LAY £10 any runner whose lay price
# is 3.0-10.0 (band 3-5 / 5-10). Settlement nightly 05:50 via listMarketBook (CLOSED, runner status WINNER/LOSER). £2 live after 60
# settled paper lays if both bands hold. Liability note: lay stake £10 at 5.0 = £40 liability; live stake will be sized by liability.
mkdir -p /root/pe-tennis2 && cat > /root/pe-tennis2/dog_paper.py <<'PYFILE'
import sys, time, datetime, requests, psycopg2
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
sys.path.insert(0,'/root/pe-queue/runner'); import creds
APP_KEY,USER,PW=creds.betfair(); TOK=None; TOK_T=0
def login():
    global TOK,TOK_T
    r=requests.post("https://identitysso.betfair.com/api/login",data={"username":USER,"password":PW},headers={"X-Application":APP_KEY,"Accept":"application/json"},timeout=15).json()
    if r.get('status')!='SUCCESS': raise SystemExit("LOGIN FAILED: "+str(r))
    TOK=r['token']; TOK_T=time.time()
def api(ep,payload):
    if TOK is None or time.time()-TOK_T>3000: login()
    r=requests.post(f"https://api.betfair.com/exchange/betting/rest/v1.0/{ep}/",json=payload,headers={"X-Authentication":TOK,"X-Application":APP_KEY,"Content-Type":"application/json","Accept":"application/json"},timeout=20)
    r.raise_for_status(); return r.json()
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("""CREATE TABLE IF NOT EXISTS tennis_dog_paper (id SERIAL PRIMARY KEY, ts TIMESTAMPTZ DEFAULT now(), market_id TEXT, event_name TEXT, competition TEXT, start_time TIMESTAMPTZ, sel_id BIGINT, sel_name TEXT,
  back_px NUMERIC, lay_px NUMERIC, band TEXT, total_matched NUMERIC, result TEXT, pnl_per_10 NUMERIC, settled_at TIMESTAMPTZ, UNIQUE (market_id, sel_id));
CREATE TABLE IF NOT EXISTS tennis_dog_heartbeat (id INT PRIMARY KEY, last_seen TIMESTAMPTZ, recorded_today INT)""")
done=set(); last_hb=0
while True:
    try:
        now=datetime.datetime.now(datetime.timezone.utc)
        cat=api('listMarketCatalogue',{"filter":{"eventTypeIds":["2"],"marketTypeCodes":["MATCH_ODDS"],"marketStartTime":{"from":(now+datetime.timedelta(minutes=1)).isoformat(),"to":(now+datetime.timedelta(minutes=4)).isoformat()}},
                "marketProjection":["EVENT","COMPETITION","RUNNER_DESCRIPTION","MARKET_START_TIME"],"maxResults":100})
        ids=[m['marketId'] for m in cat if m['marketId'] not in done]
        for i in range(0,len(ids),10):
            books={b['marketId']:b for b in api('listMarketBook',{"marketIds":ids[i:i+10],"priceProjection":{"priceData":["EX_BEST_OFFERS"]}})}
            for m in cat:
                mid=m['marketId']; b=books.get(mid)
                if not b or b.get('inplay'): continue
                names={r['selectionId']:r['runnerName'] for r in m['runners']}; st=datetime.datetime.fromisoformat(m['marketStartTime'].replace('Z','+00:00'))
                for r in b.get('runners',[]):
                    ex=r.get('ex',{}); bk=ex.get('availableToBack',[]); ly=ex.get('availableToLay',[])
                    if not bk or not ly: continue
                    lp=ly[0]['price']; band='3-5' if 3.0<=lp<=5.0 else ('5-10' if 5.0<lp<=10.0 else None)
                    cur.execute("INSERT INTO tennis_dog_paper (market_id,event_name,competition,start_time,sel_id,sel_name,back_px,lay_px,band,total_matched) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) ON CONFLICT DO NOTHING",
                                (mid,m['event']['name'],(m.get('competition') or {}).get('name',''),st,r['selectionId'],names.get(r['selectionId'],''),bk[0]['price'],lp,band,b.get('totalMatched')))
                    if band: print(f"PAPER LAY {m['event']['name']} {names.get(r['selectionId'])} @ {lp} [{band}]",flush=True)
                done.add(mid)
        if time.time()-last_hb>60:
            cur.execute("INSERT INTO tennis_dog_heartbeat VALUES (1,now(),(SELECT count(*) FROM tennis_dog_paper WHERE ts::date=current_date)) ON CONFLICT (id) DO UPDATE SET last_seen=now(), recorded_today=EXCLUDED.recorded_today"); last_hb=time.time()
        time.sleep(60)
    except Exception as e:
        print("loop",repr(e)[:200],flush=True); time.sleep(60)
        try: con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
        except Exception: pass
PYFILE
cat > /root/pe-tennis2/settle.py <<'PYFILE'
import sys, time, requests, psycopg2
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
sys.path.insert(0,'/root/pe-queue/runner'); import creds
APP_KEY,USER,PW=creds.betfair()
r=requests.post("https://identitysso.betfair.com/api/login",data={"username":USER,"password":PW},headers={"X-Application":APP_KEY,"Accept":"application/json"},timeout=15).json(); TOK=r['token']
def api(ep,payload):
    r=requests.post(f"https://api.betfair.com/exchange/betting/rest/v1.0/{ep}/",json=payload,headers={"X-Authentication":TOK,"X-Application":APP_KEY,"Content-Type":"application/json","Accept":"application/json"},timeout=20); r.raise_for_status(); return r.json()
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("SELECT DISTINCT market_id FROM tennis_dog_paper WHERE result IS NULL AND start_time < now()-interval '2 hours'"); mids=[r[0] for r in cur.fetchall()]
for i in range(0,len(mids),10):
    for b in api('listMarketBook',{"marketIds":mids[i:i+10]}):
        if b.get('status')!='CLOSED': continue
        for r in b.get('runners',[]):
            st=r.get('status')
            if st not in ('WINNER','LOSER'): continue
            cur.execute("UPDATE tennis_dog_paper SET result=%s, settled_at=now(), pnl_per_10=CASE WHEN band IS NULL THEN NULL WHEN %s='WINNER' THEN -(lay_px-1)*10 ELSE 9.8 END WHERE market_id=%s AND sel_id=%s",(st,st,b['marketId'],r['selectionId']))
cur.execute("SELECT band, count(*) n, count(result) settled, round(sum(pnl_per_10)::numeric,2) pnl, round(avg(pnl_per_10)::numeric,2) per_lay FROM tennis_dog_paper WHERE band IS NOT NULL GROUP BY 1 ORDER BY 1"); print("TENNIS DOG LAY paper:",cur.fetchall())
PYFILE
python3 -m py_compile /root/pe-tennis2/dog_paper.py /root/pe-tennis2/settle.py || exit 1
cat > /root/pe-tennis2/keepalive.sh <<'SH'
#!/bin/bash
pgrep -f dog_paper.py >/dev/null || (cd /root/pe-tennis2 && nohup python3 dog_paper.py >> dog.log 2>&1 &)
SH
chmod +x /root/pe-tennis2/keepalive.sh
( crontab -l 2>/dev/null | grep -v pe-tennis2 ; echo "* * * * * /root/pe-tennis2/keepalive.sh" ; echo "50 5 * * * cd /root/pe-tennis2 && python3 settle.py >> dog.log 2>&1" ) | crontab -
/root/pe-tennis2/keepalive.sh; sleep 75; pgrep -af dog_paper.py; tail -5 /root/pe-tennis2/dog.log
