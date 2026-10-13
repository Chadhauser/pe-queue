#!/bin/bash
# 049: MULTI-SPORT IN-PLAY TAPE RECORDER — the data every non-football scan needs and we do not hold. One daemon (own dir,
# own cron keepalive, separate from the football recorder) records every IN-PLAY market for: tennis (2), horse racing (7),
# greyhounds (4237), cricket (4), basketball (7522). Every ~3s: best 3 levels each side, LTP, total matched, status, per runner,
# into ip_tape (1 row per runner per loop) and ip_reopen (every SUSPENDED->OPEN with a 5pct+ LTP move = point/break/set/wicket/
# incident, with pre/post price). Tennis MATCH_ODDS + SET_WINNER, racing/greyhound WIN + PLACE, cricket MATCH_ODDS + innings runs
# lines are skipped (MO only), basketball MATCH_ODDS + handicap skipped (MO only). Sampler trims to 1 row/runner/15s on ip_tape
# when more than 60 markets are live so request weight stays legal. Scans 050+ read these after 7 days.
mkdir -p /root/pe-ip && cat > /root/pe-ip/ip_recorder.py <<'PYFILE'
import os, sys, time, datetime, collections, requests, psycopg2, psycopg2.extras
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
sys.path.insert(0,'/root/pe-queue/runner'); import creds
print(creds.report(),flush=True); APP_KEY,USER,PW=creds.betfair()
if not (APP_KEY and USER and PW): sys.exit("NO BETFAIR CREDENTIALS found by creds.py")
SPORTS={'2':('tennis',['MATCH_ODDS','SET_WINNER']),'7':('racing',['WIN','PLACE']),'4237':('greyhounds',['WIN','PLACE']),
        '4':('cricket',['MATCH_ODDS']),'7522':('basketball',['MATCH_ODDS'])}
TOK=None; TOK_T=0
def login():
    global TOK,TOK_T
    r=requests.post("https://identitysso.betfair.com/api/login",data={"username":USER,"password":PW},headers={"X-Application":APP_KEY,"Accept":"application/json"},timeout=15).json()
    if r.get('status')!='SUCCESS': raise SystemExit("LOGIN FAILED: "+str(r))
    TOK=r['token']; TOK_T=time.time()
def api(ep,payload):
    if TOK is None or time.time()-TOK_T>3000: login()
    r=requests.post(f"https://api.betfair.com/exchange/betting/rest/v1.0/{ep}/",json=payload,headers={"X-Authentication":TOK,"X-Application":APP_KEY,"Content-Type":"application/json","Accept":"application/json"},timeout=20)
    if r.status_code!=200: print("API",ep,r.status_code,r.text[:200],flush=True); r.raise_for_status()
    return r.json()
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("""CREATE TABLE IF NOT EXISTS ip_tape (ts TIMESTAMPTZ, sport TEXT, market_id TEXT, event_name TEXT, competition TEXT, market_type TEXT,
  market_start TIMESTAMPTZ, status TEXT, secs_since_start INT, sel_id BIGINT, sel_name TEXT, ltp NUMERIC, back_px NUMERIC, back_sz NUMERIC, lay_px NUMERIC, lay_sz NUMERIC,
  back3_sz NUMERIC, lay3_sz NUMERIC, total_matched NUMERIC);
CREATE INDEX IF NOT EXISTS ip_tape_mkt ON ip_tape (market_id, ts);
CREATE INDEX IF NOT EXISTS ip_tape_sport_ts ON ip_tape (sport, ts);
CREATE TABLE IF NOT EXISTS ip_reopen (id SERIAL PRIMARY KEY, ts TIMESTAMPTZ, sport TEXT, market_id TEXT, event_name TEXT, competition TEXT, market_type TEXT,
  secs_since_start INT, suspended_secs NUMERIC, sel_id BIGINT, sel_name TEXT, pre_ltp NUMERIC, post_ltp NUMERIC, post_back_px NUMERIC, post_lay_px NUMERIC, total_matched NUMERIC);
CREATE TABLE IF NOT EXISTS ip_heartbeat (id INT PRIMARY KEY, last_seen TIMESTAMPTZ, live_markets INT, reopens_seen INT, by_sport TEXT)""")
cat={}; last=collections.defaultdict(dict); status={}; susp_t={}; reopens=0; last_cat=0; last_hb=0
def refresh_catalogue():
    global cat,last_cat
    new={}
    for etid,(sport,mts) in SPORTS.items():
        try:
            res=api('listMarketCatalogue',{"filter":{"eventTypeIds":[etid],"marketTypeCodes":mts,"inPlayOnly":True},
                   "marketProjection":["EVENT","COMPETITION","RUNNER_DESCRIPTION","MARKET_START_TIME","MARKET_DESCRIPTION"],"maxResults":200})
        except Exception as e: print("catalogue",sport,repr(e)[:100],flush=True); continue
        for m in res:
            try: st=datetime.datetime.fromisoformat(m['marketStartTime'].replace('Z','+00:00'))
            except Exception: st=datetime.datetime.now(datetime.timezone.utc)
            new[m['marketId']]={'sport':sport,'event':m['event']['name'],'comp':(m.get('competition') or {}).get('name',''),'mt':m.get('description',{}).get('marketType') or '',
                                'start':st,'runners':{r['selectionId']:r['runnerName'] for r in m['runners']}}
    # markets that just left in-play are kept 2 more minutes so their close is captured
    for mid,meta in cat.items():
        if mid not in new and meta.get('gone') is None: meta['gone']=time.time(); new[mid]=meta
        elif mid not in new and time.time()-meta['gone']<120: new[mid]=meta
    cat=new; last_cat=time.time()
def books(ids):
    out=[]
    for i in range(0,len(ids),10):
        chunk=ids[i:i+10]
        try: out+=api('listMarketBook',{"marketIds":chunk,"priceProjection":{"priceData":["EX_BEST_OFFERS"],"exBestOffersOverrides":{"bestPricesDepth":3}}})
        except Exception as e: print("batch skipped:",repr(e)[:100],flush=True)
    return out
def rows_of(mb,meta,now):
    out=[]; ss=int((now-meta['start']).total_seconds())
    for r in mb.get('runners',[]):
        if r.get('status') not in (None,'ACTIVE'): continue
        ex=r.get('ex',{}); b=ex.get('availableToBack',[]); l=ex.get('availableToLay',[])
        out.append((now,meta['sport'],mb['marketId'],meta['event'],meta['comp'],meta['mt'],meta['start'],mb.get('status'),ss,r['selectionId'],meta['runners'].get(r['selectionId'],str(r['selectionId'])),
                    r.get('lastPriceTraded'),(b[0]['price'] if b else None),(b[0]['size'] if b else None),(l[0]['price'] if l else None),(l[0]['size'] if l else None),
                    sum(x['size'] for x in b[:3]),sum(x['size'] for x in l[:3]),mb.get('totalMatched')))
    return out
refresh_catalogue(); print("recorder up; live markets",len(cat),collections.Counter(m['sport'] for m in cat.values()),flush=True)
last_write=collections.defaultdict(float)
while True:
    try:
        now=datetime.datetime.now(datetime.timezone.utc)
        if time.time()-last_cat>45: refresh_catalogue()
        ids=list(cat.keys())
        if not ids: time.sleep(15); continue
        mbs={mb['marketId']:mb for mb in books(ids)}
        thin=len(ids)>60; rows=[]
        for mid,mb in mbs.items():
            meta=cat[mid]; st=mb.get('status'); prev=status.get(mid); status[mid]=st
            ltp={r['selectionId']:r.get('lastPriceTraded') for r in mb.get('runners',[])}
            if st=='SUSPENDED' and prev!='SUSPENDED': susp_t[mid]=time.time()
            if prev=='SUSPENDED' and st=='OPEN':
                moved=[s for s in ltp if last[mid].get(s) and ltp.get(s) and abs(ltp[s]/last[mid][s]-1)>=0.05]
                if moved:
                    reopens+=1; ss=int((now-meta['start']).total_seconds()); sd=round(time.time()-susp_t.get(mid,time.time()),1)
                    for r in mb.get('runners',[]):
                        s=r['selectionId']; ex=r.get('ex',{}); b=ex.get('availableToBack',[]); l=ex.get('availableToLay',[])
                        cur.execute("INSERT INTO ip_reopen (ts,sport,market_id,event_name,competition,market_type,secs_since_start,suspended_secs,sel_id,sel_name,pre_ltp,post_ltp,post_back_px,post_lay_px,total_matched) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)",
                            (now,meta['sport'],mid,meta['event'],meta['comp'],meta['mt'],ss,sd,s,meta['runners'].get(s,str(s)),last[mid].get(s),ltp.get(s),(b[0]['price'] if b else None),(l[0]['price'] if l else None),mb.get('totalMatched')))
            if st=='OPEN': last[mid]={s:p for s,p in ltp.items() if p}
            if (not thin) or time.time()-last_write[mid]>=15 or prev!=st:
                last_write[mid]=time.time(); rows+=rows_of(mb,meta,now)
        if rows: psycopg2.extras.execute_values(cur,"INSERT INTO ip_tape VALUES %s",rows)
        if time.time()-last_hb>60:
            last_hb=time.time(); bs=dict(collections.Counter(m['sport'] for m in cat.values()))
            cur.execute("INSERT INTO ip_heartbeat (id,last_seen,live_markets,reopens_seen,by_sport) VALUES (1,NOW(),%s,%s,%s) ON CONFLICT (id) DO UPDATE SET last_seen=NOW(), live_markets=EXCLUDED.live_markets, reopens_seen=EXCLUDED.reopens_seen, by_sport=EXCLUDED.by_sport",(len(ids),reopens,str(bs)))
        time.sleep(3)
    except SystemExit: raise
    except Exception as e:
        print("loop error",repr(e)[:200],flush=True); time.sleep(10)
        try: con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
        except Exception: pass
PYFILE
cat > /root/pe-ip/keepalive.sh <<'SH'
#!/bin/bash
exec 8>/root/pe-ip/recorder.lock; flock -n 8 || exit 0
cd /root/pe-ip && python3 ip_recorder.py >> /root/pe-ip/recorder.log 2>&1
SH
chmod +x /root/pe-ip/keepalive.sh
python3 -m py_compile /root/pe-ip/ip_recorder.py || exit 1
# smoke test only (timeout, not a daemon - cron starts the real one); lock fd closed by the runner
timeout 40 python3 /root/pe-ip/ip_recorder.py > /root/pe-ip/smoke.log 2>&1
cat /root/pe-ip/smoke.log | head -20
grep -q "recorder up" /root/pe-ip/smoke.log || { echo "SMOKE TEST FAILED - not installing cron"; exit 1; }
( crontab -l 2>/dev/null | grep -v pe-ip/keepalive ; echo "* * * * * /root/pe-ip/keepalive.sh" ) | crontab -
echo "CRON INSTALLED: multi-sport in-play recorder (tennis, racing, greyhounds, cricket, basketball). Tables: ip_tape, ip_reopen, ip_heartbeat"
