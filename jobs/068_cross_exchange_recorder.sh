#!/bin/bash
# 068: CROSS-EXCHANGE RECORDER (Peter's third test, approved 14 Oct): Smarkets + Matchbook prices alongside Betfair for the same
# in-play football/tennis/basketball match-odds markets, every 5s, so "back where too high / lay where too low" can be measured,
# especially in the minute after a goal. WAITS (exit 75) until SMARKETS_USERNAME/SMARKETS_PASSWORD and/or MATCHBOOK_USERNAME/
# MATCHBOOK_PASSWORD are in /root/pe-logger/.env; records whichever exchange has credentials. Betfair side comes from the existing
# liq_sample (football, 1/min) and ip_tape (tennis/basketball, 3s) — aligned later by event name + time. Tables: xx_tape, xx_heartbeat.
mkdir -p /root/pe-xx && cat > /root/pe-xx/xx_recorder.py <<'PYFILE'
import os, sys, time, json, datetime, re, requests, psycopg2, psycopg2.extras
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
sys.path.insert(0,'/root/pe-queue/runner'); import creds
E=creds.all_vars()
SM_U,SM_P=E.get('SMARKETS_USERNAME'),E.get('SMARKETS_PASSWORD'); MB_U,MB_P=E.get('MATCHBOOK_USERNAME'),E.get('MATCHBOOK_PASSWORD')
if not ((SM_U and SM_P) or (MB_U and MB_P)): print("WAITING: no Smarkets or Matchbook credentials in .env"); sys.exit(75)
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("""CREATE TABLE IF NOT EXISTS xx_tape (ts TIMESTAMPTZ, exchange TEXT, sport TEXT, event_name TEXT, market_id TEXT, market_name TEXT, start_ts TIMESTAMPTZ, inplay BOOLEAN,
  sel_name TEXT, back_px NUMERIC, back_sz NUMERIC, lay_px NUMERIC, lay_sz NUMERIC, ltp NUMERIC); CREATE INDEX IF NOT EXISTS xx_tape_ev ON xx_tape (exchange, event_name, ts);
  CREATE TABLE IF NOT EXISTS xx_heartbeat (exchange TEXT PRIMARY KEY, last_seen TIMESTAMPTZ, live_markets INT, note TEXT)""")
S=requests.Session(); S.headers['User-Agent']='pe-xx/1.0'
# ---------------- Smarkets (api.smarkets.com/v3) ----------------
SM_TOK=None; SM_T=0
def sm_login():
    global SM_TOK,SM_T
    r=S.post("https://api.smarkets.com/v3/sessions/",json={"username":SM_U,"password":SM_P},timeout=20).json()
    SM_TOK=r.get('token'); SM_T=time.time()
    if not SM_TOK: raise SystemExit("SMARKETS LOGIN FAILED: "+str(r)[:200])
def sm(url,params=None):
    if SM_TOK is None or time.time()-SM_T>3000: sm_login()
    r=S.get("https://api.smarkets.com/v3/"+url,params=params,headers={"Authorization":"Session-Token "+SM_TOK},timeout=20); r.raise_for_status(); return r.json()
SM_SPORT={'football':'football','tennis':'tennis','basketball':'basketball'}
def sm_snapshot(now):
    rows=[]; live=0
    for sport in SM_SPORT.values():
        ev=sm("events/",{"state":"live","type_domain":sport,"limit":200}).get('events',[])
        if not ev: continue
        live+=len(ev); ids=",".join(str(e['id']) for e in ev); emap={str(e['id']):e for e in ev}
        mk=sm(f"events/{ids}/markets/",{"limit":500}).get('markets',[])
        mk=[m for m in mk if (m.get('market_type',{}).get('name') or m.get('name','')).lower() in ('winner','match odds','match winner','winner (90 min)','winner 90 mins')] or mk[:3*len(ev)]
        if not mk: continue
        mids=[m['id'] for m in mk]
        ct=sm(f"markets/{','.join(mids)}/contracts/",{"limit":1000}).get('contracts',[]); cmap={c['id']:c for c in ct}
        q=sm(f"markets/{','.join(mids)}/quotes/")
        for m in mk:
            e=emap.get(str(m['event_id']),{})
            for cid,qq in q.items():
                c=cmap.get(cid)
                if not c or c['market_id']!=m['id']: continue
                bids=qq.get('bids',[]); offers=qq.get('offers',[])
                # Smarkets prices are in percent*100 (e.g. 2500 = 25% = 4.0); quantities in pennies*100
                bp=(10000/bids[0]['price']) if bids else None; bs=(bids[0]['quantity']/10000) if bids else None
                lp=(10000/offers[0]['price']) if offers else None; ls=(offers[0]['quantity']/10000) if offers else None
                lt=qq.get('last_executed_price'); lt=(10000/lt) if lt else None
                rows.append((now,'smarkets',sport,e.get('name'),str(m['id']),m.get('name'),e.get('start_datetime'),True,c.get('name'),bp,bs,lp,ls,lt))
    return rows,live
# ---------------- Matchbook (api.matchbook.com) ----------------
MB_TOK=None; MB_T=0
def mb_login():
    global MB_TOK,MB_T
    r=S.post("https://api.matchbook.com/bpapi/rest/security/session",json={"username":MB_U,"password":MB_P},headers={"Accept":"application/json"},timeout=20).json()
    MB_TOK=r.get('session-token'); MB_T=time.time()
    if not MB_TOK: raise SystemExit("MATCHBOOK LOGIN FAILED: "+str(r)[:200])
def mb(url,params=None):
    if MB_TOK is None or time.time()-MB_T>3000: mb_login()
    r=S.get("https://api.matchbook.com/edge/rest/"+url,params=params,headers={"session-token":MB_TOK,"Accept":"application/json"},timeout=20); r.raise_for_status(); return r.json()
MB_SPORT={'football':15,'tennis':9,'basketball':1}
def mb_snapshot(now):
    rows=[]; live=0
    for sport,sid in MB_SPORT.items():
        ev=mb("events",{"sport-ids":sid,"states":"open","in-running-flag":"true","include-prices":"true","price-depth":1,"odds-type":"DECIMAL","per-page":200,"market-names":"Match Odds"}).get('events',[])
        live+=len(ev)
        for e in ev:
            for m in e.get('markets',[]):
                if 'match odds' not in (m.get('name') or '').lower() and m.get('market-type')!='one_x_two': continue
                for r in m.get('runners',[]):
                    b=[p for p in r.get('prices',[]) if p.get('side')=='back']; l=[p for p in r.get('prices',[]) if p.get('side')=='lay']
                    rows.append((now,'matchbook',sport,e.get('name'),str(m.get('id')),m.get('name'),e.get('start'),e.get('in-running-flag'),r.get('name'),
                                 b[0]['decimal-odds'] if b else None,b[0]['available-amount'] if b else None,l[0]['decimal-odds'] if l else None,l[0]['available-amount'] if l else None,None))
    return rows,live
print("recorder up; smarkets",bool(SM_U),"matchbook",bool(MB_U),flush=True)
while True:
    now=datetime.datetime.now(datetime.timezone.utc)
    for name,fn,on in (('smarkets',sm_snapshot,bool(SM_U and SM_P)),('matchbook',mb_snapshot,bool(MB_U and MB_P))):
        if not on: continue
        try:
            rows,live=fn(now)
            if rows: psycopg2.extras.execute_values(cur,"INSERT INTO xx_tape VALUES %s",rows)
            cur.execute("INSERT INTO xx_heartbeat VALUES (%s,NOW(),%s,'ok') ON CONFLICT (exchange) DO UPDATE SET last_seen=NOW(), live_markets=EXCLUDED.live_markets, note='ok'",(name,live))
        except SystemExit as e: print(e,flush=True); cur.execute("INSERT INTO xx_heartbeat VALUES (%s,NOW(),0,%s) ON CONFLICT (exchange) DO UPDATE SET last_seen=NOW(), note=EXCLUDED.note",(name,str(e)[:200])); time.sleep(300)
        except Exception as e: print(name,"error",repr(e)[:160],flush=True); time.sleep(10)
    time.sleep(5)
PYFILE
cat > /root/pe-xx/keepalive.sh <<'SH'
#!/bin/bash
exec 8>/root/pe-xx/recorder.lock; flock -n 8 || exit 0
cd /root/pe-xx && python3 xx_recorder.py >> /root/pe-xx/recorder.log 2>&1
SH
chmod +x /root/pe-xx/keepalive.sh; python3 -m py_compile /root/pe-xx/xx_recorder.py || exit 1
timeout 40 python3 /root/pe-xx/xx_recorder.py > /root/pe-xx/smoke.log 2>&1; rc=$?
cat /root/pe-xx/smoke.log | head -20
grep -q "WAITING" /root/pe-xx/smoke.log && exit 75
grep -q "recorder up" /root/pe-xx/smoke.log || { echo "SMOKE TEST FAILED"; exit 1; }
( crontab -l 2>/dev/null | grep -v pe-xx/keepalive ; echo "* * * * * /root/pe-xx/keepalive.sh" ) | crontab -
echo "CRON INSTALLED: cross-exchange recorder. Tables: xx_tape, xx_heartbeat"
