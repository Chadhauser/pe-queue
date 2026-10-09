#!/bin/bash
# 013: LIVE LIQUIDITY RECORDER (the Basic history has no volume, so this is measured live). Installs a daemon kept alive by
# cron. Every 4s it reads the full ladder (EX_ALL_OFFERS) of every in-play football MATCH_ODDS and OVER_UNDER_25 market.
# A goal = market suspended then reopened with a 10pct+ move on some runner. For each goal it stores, at reopen, +30s, +60s,
# +120s, +300s: best back/lay price+size, size available within 3 ticks each side, total matched, matched since the goal.
# Table liq_goal_depth. Also a once-a-minute sample of every live market (liq_sample) so liquidity can be sized by league,
# minute and price band whether or not a goal happens. Sizing job reads these after a week.
mkdir -p /root/pe-liq && cat > /root/pe-liq/liq_recorder.py <<'PYFILE'
import os, re, sys, time, json, datetime, collections, requests, psycopg2, psycopg2.extras
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
sys.path.insert(0,'/root/pe-queue/runner'); import creds
print(creds.report(),flush=True); APP_KEY,USER,PW=creds.betfair()
if not (APP_KEY and USER and PW): sys.exit("NO BETFAIR CREDENTIALS found by creds.py")
TOK=None; TOK_T=0
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
cur.execute("""CREATE TABLE IF NOT EXISTS liq_goal_depth (id SERIAL PRIMARY KEY, market_id TEXT, event_name TEXT, competition TEXT, mkt TEXT, sel TEXT,
  goal_ts TIMESTAMPTZ, offset_s INT, ts TIMESTAMPTZ, pre_ltp NUMERIC, ltp NUMERIC, back_px NUMERIC, back_sz NUMERIC, lay_px NUMERIC, lay_sz NUMERIC,
  back3_sz NUMERIC, lay3_sz NUMERIC, total_matched NUMERIC, matched_since_goal NUMERIC, minute INT);
CREATE TABLE IF NOT EXISTS liq_sample (ts TIMESTAMPTZ, market_id TEXT, event_name TEXT, competition TEXT, mkt TEXT, sel TEXT, minute INT, ltp NUMERIC,
  back_px NUMERIC, back_sz NUMERIC, lay_px NUMERIC, lay_sz NUMERIC, back3_sz NUMERIC, lay3_sz NUMERIC, total_matched NUMERIC);
CREATE TABLE IF NOT EXISTS liq_heartbeat (id INT PRIMARY KEY, last_seen TIMESTAMPTZ, live_markets INT, goals_seen INT)""")
def ticks_within(ladder,px,n,side):
    # size available at the best n price levels (ladder already sorted best-first)
    return sum(l['size'] for l in ladder[:n])
cat={}   # market_id -> meta
last=collections.defaultdict(dict)  # market_id -> {sel: ltp}
status={}  # market_id -> last status
pending=[] # (market_id, goal_ts, pre_ltp by sel, matched_at_goal, due offsets list)
goals=0; last_cat=0; last_sample=0
def refresh_catalogue():
    global cat,last_cat
    now=datetime.datetime.utcnow()
    new={}
    for mt in ('MATCH_ODDS','OVER_UNDER_25'):
        res=api('listMarketCatalogue',{"filter":{"eventTypeIds":["1"],"marketTypeCodes":[mt],"inPlayOnly":True},
               "marketProjection":["EVENT","COMPETITION","RUNNER_DESCRIPTION","MARKET_START_TIME"],"maxResults":200})
        for m in res:
            try: st=datetime.datetime.fromisoformat(m['marketStartTime'].replace('Z','+00:00')).replace(tzinfo=None)
            except Exception: st=now
            new[m['marketId']]={'event':m['event']['name'],'comp':(m.get('competition') or {}).get('name',''),'mkt':'MO' if mt=='MATCH_ODDS' else 'OU25',
                                'start':st,'runners':{r['selectionId']:r['runnerName'] for r in m['runners']}}
    cat=new; last_cat=time.time()
def selname(meta,sid):
    n=meta['runners'].get(sid,str(sid)); low=n.lower()
    if meta['mkt']=='OU25': return 'OVER' if low.startswith('over') else 'UNDER'
    if 'draw' in low: return 'DRAW'
    h=meta['event'].split(' v ')[0] if ' v ' in meta['event'] else ''
    return 'HOME' if n.strip()==h.strip() else 'AWAY'
def minute_of(meta,now):
    # elapsed since scheduled start, minus a 15-min break once past 60 wall-clock minutes (rough; good enough for banding)
    el=(now-meta['start']).total_seconds()/60
    return int(el if el<=47 else max(45,el-15.5))
def books(ids):
    out=[]
    for i in range(0,len(ids),20):
        out+=api('listMarketBook',{"marketIds":ids[i:i+20],"priceProjection":{"priceData":["EX_ALL_OFFERS","EX_TRADED"]}})
    return out
def rec_rows(mb,meta,now):
    rows=[]
    for r in mb.get('runners',[]):
        ex=r.get('ex',{}); b=ex.get('availableToBack',[]); l=ex.get('availableToLay',[])
        rows.append((selname(meta,r['selectionId']),r.get('lastPriceTraded'),(b[0]['price'] if b else None),(b[0]['size'] if b else None),
                     (l[0]['price'] if l else None),(l[0]['size'] if l else None),ticks_within(b,None,3,'b'),ticks_within(l,None,3,'l'),mb.get('totalMatched')))
    return rows
refresh_catalogue(); print("recorder up; live markets",len(cat),flush=True)
while True:
    try:
        now=datetime.datetime.utcnow()
        if time.time()-last_cat>60: refresh_catalogue()
        ids=list(cat.keys())
        if not ids: time.sleep(20); continue
        mbs={mb['marketId']:mb for mb in books(ids)}
        for mid,mb in mbs.items():
            meta=cat[mid]; st=mb.get('status'); prev=status.get(mid); status[mid]=st
            cur_ltp={r['selectionId']:r.get('lastPriceTraded') for r in mb.get('runners',[])}
            if prev=='SUSPENDED' and st=='OPEN':
                # reopened: a goal if some runner's LTP moved 10pct+ vs before the suspension
                moved=any(last[mid].get(s) and cur_ltp.get(s) and abs(cur_ltp[s]/last[mid][s]-1)>=0.10 for s in cur_ltp)
                if moved:
                    goals+=1
                    pre={selname(meta,s):last[mid].get(s) for s in cur_ltp}
                    pending.append({'mid':mid,'ts':now,'pre':pre,'matched0':mb.get('totalMatched') or 0,'due':[0,30,60,120,300],'minute':minute_of(meta,now)})
            if st=='OPEN': last[mid]={s:p for s,p in cur_ltp.items() if p}
        # due snapshots
        for p in pending[:]:
            meta=cat.get(p['mid']); mb=mbs.get(p['mid'])
            if not meta or not mb: pending.remove(p); continue
            el=(now-p['ts']).total_seconds()
            while p['due'] and el>=p['due'][0]:
                off=p['due'].pop(0)
                for sel,ltp,bp,bs,lp,ls,b3,l3,tm in rec_rows(mb,meta,now):
                    cur.execute("INSERT INTO liq_goal_depth (market_id,event_name,competition,mkt,sel,goal_ts,offset_s,ts,pre_ltp,ltp,back_px,back_sz,lay_px,lay_sz,back3_sz,lay3_sz,total_matched,matched_since_goal,minute) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)",
                        (p['mid'],meta['event'],meta['comp'],meta['mkt'],sel,p['ts'],off,now,p['pre'].get(sel),ltp,bp,bs,lp,ls,b3,l3,tm,(tm or 0)-p['matched0'],p['minute']))
            if not p['due']: pending.remove(p)
        if time.time()-last_sample>60:
            last_sample=time.time(); rows=[]
            for mid,mb in mbs.items():
                if mb.get('status')!='OPEN': continue
                meta=cat[mid]; mn=minute_of(meta,now)
                for sel,ltp,bp,bs,lp,ls,b3,l3,tm in rec_rows(mb,meta,now):
                    rows.append((now,mid,meta['event'],meta['comp'],meta['mkt'],sel,mn,ltp,bp,bs,lp,ls,b3,l3,tm))
            if rows: psycopg2.extras.execute_values(cur,"INSERT INTO liq_sample VALUES %s",rows)
            cur.execute("INSERT INTO liq_heartbeat (id,last_seen,live_markets,goals_seen) VALUES (1,NOW(),%s,%s) ON CONFLICT (id) DO UPDATE SET last_seen=NOW(), live_markets=EXCLUDED.live_markets, goals_seen=EXCLUDED.goals_seen",(len(ids),goals))
        time.sleep(4)
    except SystemExit: raise
    except Exception as e:
        print("loop error",repr(e),flush=True); time.sleep(10)
        try: con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
        except Exception: pass
PYFILE
cat > /root/pe-liq/keepalive.sh <<'SH'
#!/bin/bash
exec 8>/root/pe-liq/recorder.lock; flock -n 8 || exit 0
cd /root/pe-liq && python3 liq_recorder.py >> /root/pe-liq/recorder.log 2>&1
SH
chmod +x /root/pe-liq/keepalive.sh
python3 -m py_compile /root/pe-liq/liq_recorder.py || exit 1
# smoke test: credentials + one catalogue call, 25s, then hand over to cron
timeout 25 python3 /root/pe-liq/liq_recorder.py > /root/pe-liq/smoke.log 2>&1; rc=$?
cat /root/pe-liq/smoke.log
grep -q "recorder up" /root/pe-liq/smoke.log || { echo "SMOKE TEST FAILED (credentials?) - not installing cron"; exit 1; }
( crontab -l 2>/dev/null | grep -v pe-liq/keepalive ; echo "* * * * * /root/pe-liq/keepalive.sh" ) | crontab -
echo "CRON INSTALLED: liquidity recorder kept alive every minute. Tables: liq_goal_depth, liq_sample, liq_heartbeat"
