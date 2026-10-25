#!/bin/bash
# 224: BETFAIR STREAMING API CLIENT — the speed layer. Persistent TLS socket to stream-api.betfair.com:443, market subscription with
# the exchange's own change stream (sub-second, no polling, no quota). Scope: horse-racing WIN markets from 12 minutes before the off
# until closed, plus in-play football MATCH_ODDS and OVER_UNDER_25. Maintains a full best-3 ladder per runner from the image + deltas
# and writes EVERY change for those markets to stream_ticks (ts_recv, pt = exchange publish time, latency_ms, market_id, sel, back/lay
# best price+size, ltp, tv, inplay, status). Market list refreshed every 60 s via listMarketCatalogue; the subscription is re-issued
# when the list changes (one subscription at a time, replacing the previous). Heartbeat table stream_heartbeat (markets, ticks/min,
# median latency). Reconnects with backoff. Creds via runner/creds.py as every other bot. Keepalive on cron.
set -e
mkdir -p /root/pe-stream && cat > /root/pe-stream/stream_client.py <<'PYFILE'
import sys, ssl, socket, json, time, datetime, threading, statistics, requests, psycopg2, psycopg2.extras
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
sys.path.insert(0,'/root/pe-queue/runner'); import creds
APP_KEY,USER,PW=creds.betfair()
if not (APP_KEY and USER and PW): sys.exit("no betfair creds")
HOST,PORT="stream-api.betfair.com",443
def login():
    r=requests.post("https://identitysso.betfair.com/api/login",data={"username":USER,"password":PW},headers={"X-Application":APP_KEY,"Accept":"application/json"},timeout=15).json()
    if r.get('status')!='SUCCESS': raise RuntimeError("LOGIN FAILED "+str(r))
    return r['token']
def api(tok,ep,payload):
    r=requests.post(f"https://api.betfair.com/exchange/betting/rest/v1.0/{ep}/",json=payload,headers={"X-Authentication":tok,"X-Application":APP_KEY,"Content-Type":"application/json","Accept":"application/json"},timeout=20)
    r.raise_for_status(); return r.json()
def connect_db():
    c=psycopg2.connect(DB,sslmode='require'); c.autocommit=True; return c
con=connect_db(); cur=con.cursor()
cur.execute("""CREATE TABLE IF NOT EXISTS stream_ticks (ts_recv TIMESTAMPTZ, pt TIMESTAMPTZ, latency_ms INT, market_id TEXT, sport TEXT, mkt TEXT, sel_id BIGINT, sel TEXT,
  back_px NUMERIC, back_sz NUMERIC, lay_px NUMERIC, lay_sz NUMERIC, back2_px NUMERIC, lay2_px NUMERIC, ltp NUMERIC, tv NUMERIC, inplay BOOLEAN, status TEXT, secs_to_off INT);
CREATE INDEX IF NOT EXISTS stream_ticks_mkt ON stream_ticks (market_id, ts_recv);
CREATE TABLE IF NOT EXISTS stream_heartbeat (id INT PRIMARY KEY, last_seen TIMESTAMPTZ, markets INT, ticks_last_min INT, median_latency_ms INT, conn_state TEXT)""")
# ---------------- market universe (polled, cheap) ----------------
universe={}   # market_id -> meta
def refresh_universe(tok):
    now=datetime.datetime.now(datetime.timezone.utc); out={}
    t0=(now-datetime.timedelta(minutes=5)).strftime('%Y-%m-%dT%H:%M:%SZ'); t1=(now+datetime.timedelta(minutes=12)).strftime('%Y-%m-%dT%H:%M:%SZ')
    try:
        for m in api(tok,'listMarketCatalogue',{"filter":{"eventTypeIds":["7"],"marketTypeCodes":["WIN"],"marketCountries":["GB","IE"],"marketStartTime":{"from":t0,"to":t1}},"marketProjection":["EVENT","RUNNER_DESCRIPTION","MARKET_START_TIME"],"maxResults":60}):
            out[m['marketId']]=dict(sport='racing',mkt='WIN',ev=m['event']['name'],start=datetime.datetime.fromisoformat(m['marketStartTime'].replace('Z','+00:00')),names={r['selectionId']:r['runnerName'] for r in m['runners']})
        for m in api(tok,'listMarketCatalogue',{"filter":{"eventTypeIds":["1"],"marketTypeCodes":["MATCH_ODDS","OVER_UNDER_25"],"inPlayOnly":True},"marketProjection":["EVENT","RUNNER_DESCRIPTION","MARKET_START_TIME","MARKET_DESCRIPTION"],"maxResults":200}):
            mt=m.get('description',{}).get('marketType') or ('MATCH_ODDS' if 'Match Odds' in m.get('marketName','') else 'OVER_UNDER_25')
            out[m['marketId']]=dict(sport='football',mkt='MO' if mt=='MATCH_ODDS' else 'OU25',ev=m['event']['name'],start=datetime.datetime.fromisoformat(m['marketStartTime'].replace('Z','+00:00')),names={r['selectionId']:r['runnerName'] for r in m['runners']})
    except Exception as e: print("catalogue",repr(e)[:150],flush=True)
    return out
# ---------------- ladder cache + delta application ----------------
books={}   # market_id -> {'status','inplay','runners':{sel_id:{'batb':{lvl:(px,sz)},'batl':{...},'ltp','tv'}}}
def apply_mc(mc):
    mid=mc['id']
    if mc.get('img'): books[mid]={'status':None,'inplay':None,'runners':{}}
    b=books.setdefault(mid,{'status':None,'inplay':None,'runners':{}})
    md=mc.get('marketDefinition')
    if md: b['status']=md.get('status'); b['inplay']=md.get('inPlay')
    changed=set()
    for rc in mc.get('rc',[]):
        r=b['runners'].setdefault(rc['id'],{'batb':{},'batl':{},'ltp':None,'tv':None}); changed.add(rc['id'])
        for lvl,px,sz in rc.get('batb',[]):
            if sz==0: r['batb'].pop(lvl,None)
            else: r['batb'][lvl]=(px,sz)
        for lvl,px,sz in rc.get('batl',[]):
            if sz==0: r['batl'].pop(lvl,None)
            else: r['batl'][lvl]=(px,sz)
        if 'ltp' in rc: r['ltp']=rc['ltp']
        if 'tv' in rc: r['tv']=rc['tv']
    return mid,changed
def best(d,lvl=0): return d.get(lvl,(None,None))
# ---------------- stream thread ----------------
state={'conn':'init','tok':None,'sub_ids':set(),'lat':[],'ticks':0}
def stream_loop():
    backoff=2
    while True:
        try:
            tok=login(); state['tok']=tok
            ctx=ssl.create_default_context(); raw=socket.create_connection((HOST,PORT),timeout=30); s=ctx.wrap_socket(raw,server_hostname=HOST); f=s.makefile('rb')
            def send(o): s.sendall((json.dumps(o)+"\r\n").encode())
            line=f.readline(); print("stream:",line.decode().strip()[:120],flush=True)
            send({"op":"authentication","id":1,"appKey":APP_KEY,"session":tok}); print("auth:",f.readline().decode().strip()[:120],flush=True)
            state['conn']='connected'; backoff=2; state['sub_ids']=set(); last_sub=0
            s.settimeout(30)
            while True:
                ids=set(universe.keys())
                if ids and (ids!=state['sub_ids'] or time.time()-last_sub>600):
                    send({"op":"marketSubscription","id":2,"marketFilter":{"marketIds":sorted(ids)[:200]},"marketDataFilter":{"fields":["EX_BEST_OFFERS_DISP","EX_LTP","EX_TRADED_VOL","EX_MARKET_DEF"],"ladderLevels":3},"conflateMs":0,"heartbeatMs":5000})
                    state['sub_ids']=set(ids); last_sub=time.time(); print("subscribed",len(ids),"markets",flush=True)
                try: line=f.readline()
                except socket.timeout: continue
                if not line: raise ConnectionError("stream closed")
                msg=json.loads(line); op=msg.get('op')
                if op=='status' and msg.get('statusCode')=='FAILURE': print("STATUS FAILURE",msg,flush=True); raise ConnectionError(str(msg))
                if op!='mcm': continue
                if msg.get('ct')=='HEARTBEAT': continue
                recv=datetime.datetime.now(datetime.timezone.utc); pt=datetime.datetime.fromtimestamp(msg['pt']/1000,datetime.timezone.utc); lat=int((recv-pt).total_seconds()*1000)
                rows=[]
                for mc in msg.get('mc',[]):
                    mid,changed=apply_mc(mc); meta=universe.get(mid)
                    if not meta: continue
                    b=books[mid]; sto=int((meta['start']-recv).total_seconds())
                    for sid in changed:
                        r=b['runners'][sid]; bp,bs=best(r['batb']); lp,ls=best(r['batl']); b2,_=best(r['batb'],1); l2,_=best(r['batl'],1)
                        rows.append((recv,pt,lat,mid,meta['sport'],meta['mkt'],sid,meta['names'].get(sid,str(sid)),bp,bs,lp,ls,b2,l2,r['ltp'],r['tv'],b['inplay'],b['status'],sto))
                if rows:
                    with lock: pending.extend(rows); state['lat'].append(lat); state['ticks']+=len(rows)
        except Exception as e:
            state['conn']='reconnecting: '+repr(e)[:80]; print("stream error",repr(e)[:160],"-> retry in",backoff,flush=True); time.sleep(backoff); backoff=min(60,backoff*2)
lock=threading.Lock(); pending=[]
threading.Thread(target=stream_loop,daemon=True).start()
# ---------------- main loop: universe refresh, batch writes, heartbeat ----------------
last_u=0; last_hb=0; tick_window=[]
while True:
    try:
        if time.time()-last_u>60 and state['tok']:
            u=refresh_universe(state['tok'])
            if u: universe.clear(); universe.update(u)
            # drop closed books
            for mid in [m for m in books if m not in universe]: books.pop(mid,None)
            last_u=time.time()
        with lock: rows=pending[:]; pending.clear(); lats=state['lat'][-500:]; state['lat']=lats
        if rows:
            psycopg2.extras.execute_values(cur,"INSERT INTO stream_ticks VALUES %s",rows,page_size=1000); tick_window.append((time.time(),len(rows)))
        tick_window=[(t,n) for t,n in tick_window if time.time()-t<60]
        if time.time()-last_hb>30:
            cur.execute("INSERT INTO stream_heartbeat VALUES (1,now(),%s,%s,%s,%s) ON CONFLICT (id) DO UPDATE SET last_seen=now(), markets=EXCLUDED.markets, ticks_last_min=EXCLUDED.ticks_last_min, median_latency_ms=EXCLUDED.median_latency_ms, conn_state=EXCLUDED.conn_state",
                        (len(universe),sum(n for _,n in tick_window),int(statistics.median(lats)) if lats else None,state['conn'][:120])); last_hb=time.time()
        time.sleep(1)
    except Exception as e:
        print("main",repr(e)[:160],flush=True); time.sleep(5)
        try: con=connect_db(); cur=con.cursor()
        except Exception: pass
PYFILE
python3 -m py_compile /root/pe-stream/stream_client.py
python3 - <<'PY'
# unit test: image + deltas produce the right best prices; zero-size removes a level
import importlib.util, types, sys
src=open('/root/pe-stream/stream_client.py').read(); i=src.index("books={}"); j=src.index("# ---------------- stream thread")
ns={}; exec(src[i:j],ns)
ns['apply_mc']({'id':'1.1','img':True,'rc':[{'id':11,'batb':[[0,2.0,50],[1,1.98,20]],'batl':[[0,2.02,30]],'ltp':2.0,'tv':1000}]})
ns['apply_mc']({'id':'1.1','rc':[{'id':11,'batb':[[0,2.02,10]],'batl':[[0,2.02,0],[0,2.04,40]],'ltp':2.02}]})
r=ns['books']['1.1']['runners'][11]; print(r)
assert ns['best'](r['batb'])==(2.02,10) and ns['best'](r['batl'])==(2.04,40) and r['ltp']==2.02 and r['tv']==1000
print("delta test PASS")
PY
cat > /root/pe-stream/keepalive.sh <<'SH'
#!/bin/bash
pgrep -f stream_client.py >/dev/null || (cd /root/pe-stream && nohup python3 stream_client.py >> stream.log 2>&1 &)
SH
chmod +x /root/pe-stream/keepalive.sh
( crontab -l 2>/dev/null | grep -v "pe-stream/keepalive" ; echo "* * * * * /root/pe-stream/keepalive.sh" ) | crontab -
/root/pe-stream/keepalive.sh; sleep 90; pgrep -af stream_client.py | head -1; tail -8 /root/pe-stream/stream.log
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require').cursor()
c.execute("SELECT * FROM stream_heartbeat"); print("heartbeat (markets, ticks/min, median latency ms, state):",c.fetchall())
c.execute("SELECT sport, mkt, count(*), count(DISTINCT market_id), round(avg(latency_ms)) lat FROM stream_ticks WHERE ts_recv>now()-interval '2 minutes' GROUP BY 1,2"); print("ticks by sport/mkt last 2 min:",c.fetchall())
c.execute("SELECT ts_recv, latency_ms, sel, back_px, back_sz, lay_px, lay_sz, ltp, secs_to_off FROM stream_ticks WHERE sport='racing' ORDER BY ts_recv DESC LIMIT 5"); [print("  ",r) for r in c.fetchall()]
PY
