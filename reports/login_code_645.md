# 645 — 2026-11-17 14:04 UTC
stream file: /root/pe-stream/stream_client.py
```python
1:import sys as _s553; _s553.path.insert(0,'/root/pe-liq'); import bf_chunk  # 553: listMarketCatalogue TOO_MUCH_DATA -> bisect (same guard as the liq recorder)
2:import sys, ssl, socket, json, time, datetime, threading, statistics, requests, psycopg2, psycopg2.extras
8:def login():
9:    r=requests.post("https://identitysso.betfair.com/api/login",data={"username":USER,"password":PW},headers={"X-Application":APP_KEY,"Accept":"application/json"},timeout=15).json()
12:def api(tok,ep,payload):
15:def connect_db():
16:    c=psycopg2.connect(DB,sslmode='require'); c.autocommit=True; return c
24:def _passed_types():
27:        c=_pg.connect(_cr.pg_local(),sslmode='disable').cursor(); c.execute("SELECT DISTINCT market_type FROM fair_price_passed WHERE sport='Soccer'"); return sorted({t for (t,) in c.fetchall()}|{'MATCH_ODDS'})
28:    except Exception as e: print("passed types read failed",repr(e)[:80],flush=True); return ['MATCH_ODDS']
29:def refresh_universe(tok):
33:        for m in api(tok,'listMarketCatalogue',{"filter":{"eventTypeIds":["7"],"marketTypeCodes":["WIN"],"marketCountries":["GB","IE"],"marketStartTime":{"from":t0,"to":t1}},"marketProjection":["EVENT","RUNNER_DESCRIPTION","MARKET_START_TIME"],"maxResults":60}):
35:        for m in api(tok,'listMarketCatalogue',{"filter":{"eventTypeIds":["1"],"marketTypeCodes":["MATCH_ODDS","OVER_UNDER_25"],"inPlayOnly":True},"marketProjection":["EVENT","RUNNER_DESCRIPTION","MARKET_START_TIME","MARKET_DESCRIPTION"],"maxResults":200}):
38:        for m in api(tok,'listMarketCatalogue',{"filter":{"eventTypeIds":["2"],"marketTypeCodes":["MATCH_ODDS"],"inPlayOnly":True},"marketProjection":["EVENT","RUNNER_DESCRIPTION","MARKET_START_TIME"],"maxResults":40,"sort":"MAXIMUM_TRADED"}):
41:        for m in api(tok,'listMarketCatalogue',{"filter":{"eventTypeIds":["1"],"marketTypeCodes":["MATCH_ODDS"],"inPlayOnly":False,"marketStartTime":{"from":t_now,"to":t2}},"marketProjection":["EVENT","RUNNER_DESCRIPTION","MARKET_START_TIME"],"maxResults":40,"sort":"MAXIMUM_TRADED"}):
43:    except Exception as e: print("catalogue",repr(e)[:150],flush=True)
47:        for m in api(tok,'listMarketCatalogue',{"filter":f,"marketProjection":["EVENT","RUNNER_DESCRIPTION","MARKET_START_TIME","MARKET_DESCRIPTION"],"maxResults":200}):
50:    except Exception as e: print("pre-off universe",repr(e)[:100],flush=True)
54:def apply_mc(mc):
72:def best(d,lvl=0): return d.get(lvl,(None,None))
75:def stream_loop():
77:    while True:
79:            tok=login(); state['tok']=tok
80:            ctx=ssl.create_default_context(); raw=socket.create_connection((HOST,PORT),timeout=30); s=ctx.wrap_socket(raw,server_hostname=HOST); f=s.makefile('rb')
81:            def send(o): s.sendall((json.dumps(o)+"\r\n").encode())
83:            send({"op":"authentication","id":1,"appKey":APP_KEY,"session":tok}); print("auth:",f.readline().decode().strip()[:120],flush=True)
86:            while True:
89:                    send({"op":"marketSubscription","id":2,"marketFilter":{"marketIds":sorted(ids)[:200]},"marketDataFilter":{"fields":["EX_BEST_OFFERS_DISP","EX_LTP","EX_TRADED_VOL","EX_MARKET_DEF"],"ladderLevels":3},"conflateMs":0,"heartbeatMs":5000})
90:                    state['sub_ids']=set(ids); last_sub=time.time(); print("subscribed",len(ids),"markets",flush=True)
92:                except socket.timeout:
112:        except Exception as e:
113:            state['conn']='reconnecting: '+repr(e)[:80]; print("stream error",repr(e)[:160],"-> retry in",backoff,flush=True); time.sleep(backoff); backoff=min(60,backoff*2)
118:while True:
134:    except Exception as e:
137:        except Exception: pass
```
### /root/pe-stream/stream_client.py def login (line 8)
```python
def login():
    r=requests.post("https://identitysso.betfair.com/api/login",data={"username":USER,"password=***,headers={"X-Application":APP_KEY,"Accept":"application/json"},timeout=15).json()
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
def _passed_types():
    try:
        import psycopg2 as _pg, sys as _sy; _sy.path.insert(0,'/root/pe-queue/runner'); import creds as _cr
        c=_pg.connect(_cr.pg_local(),sslmode='disable').cursor(); c.execute("SELECT DISTINCT market_type FROM fair_price_passed WHERE sport='Soccer'"); return sorted({t for (t,) in c.fetchall()}|{'MATCH_ODDS'})
    except Exception as e: print("passed types read failed",repr(e)[:80],flush=True); return ['MATCH_ODDS']
def refresh_universe(tok):
    now=datetime.datetime.now(datetime.timezone.utc); out={}
    t0=(now-datetime.timedelta(minutes=5)).strftime('%Y-%m-%dT%H:%M:%SZ'); t1=(now+datetime.timedelta(minutes=12)).strftime('%Y-%m-%dT%H:%M:%SZ')
    try:
        for m in api(tok,'listMarketCatalogue',{"filter":{"eventTypeIds":["7"],"marketTypeCodes":["WIN"],"marketCountries":["GB","IE"],"marketStartTime":{"from":t0,"to":t1}},"marketProjection":["EVENT","RUNNER_DESCRIPTION","MARKET_START_TIME"],"maxResults":60}):
            out[m['marketId']]=dict(sport='racing',mkt='WIN',ev=m['event']['name'],start=datetime.datetime.fromisoformat(m['marketStartTime'].replace('Z','+00:00')),names={r['selectionId']:r['runnerName'] for r in m['runners']})
        for m in api(tok,'listMarketCatalogue',{"filter":{"eventTypeIds":["1"],"marketTypeCodes":["MATCH_ODDS","OVER_UNDER_25"],"inPlayOnly":True},"marketProjection":["EVENT","RUNNER_DESCRIPTION","MARKET_START_TIME","MARKET_DESCRIPTION"],"maxResults":200}):
            mt=m.get('description',{}).get('marketType') or ('MATCH_ODDS' if 'Match Odds' in m.get('marketName','') else 'OVER_UNDER_25')
            out[m['marketId']]=dict(sport='football',mkt='MO' if mt=='MATCH_ODDS' else 'OU25',ev=m['event']['name'],start=datetime.datetime.fromisoformat(m['marketStartTime'].replace('Z','+00:00')),names={r['selectionId']:r['runnerName'] for r in m['runners']})
        for m in api(tok,'listMarketCatalogue',{"filter":{"eventTypeIds":["2"],"marketTypeCodes":["MATCH_ODDS"],"inPlayOnly":True},"marketProjection":["EVENT","RUNNER_DESCRIPTION","MARKET_START_TIME"],"maxResults":40,"sort":"MAXIMUM_TRADED"}):
```
### /root/pe-stream/stream_client.py def api (line 12)
```python
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
def _passed_types():
    try:
        import psycopg2 as _pg, sys as _sy; _sy.path.insert(0,'/root/pe-queue/runner'); import creds as _cr
        c=_pg.connect(_cr.pg_local(),sslmode='disable').cursor(); c.execute("SELECT DISTINCT market_type FROM fair_price_passed WHERE sport='Soccer'"); return sorted({t for (t,) in c.fetchall()}|{'MATCH_ODDS'})
    except Exception as e: print("passed types read failed",repr(e)[:80],flush=True); return ['MATCH_ODDS']
def refresh_universe(tok):
    now=datetime.datetime.now(datetime.timezone.utc); out={}
    t0=(now-datetime.timedelta(minutes=5)).strftime('%Y-%m-%dT%H:%M:%SZ'); t1=(now+datetime.timedelta(minutes=12)).strftime('%Y-%m-%dT%H:%M:%SZ')
    try:
        for m in api(tok,'listMarketCatalogue',{"filter":{"eventTypeIds":["7"],"marketTypeCodes":["WIN"],"marketCountries":["GB","IE"],"marketStartTime":{"from":t0,"to":t1}},"marketProjection":["EVENT","RUNNER_DESCRIPTION","MARKET_START_TIME"],"maxResults":60}):
            out[m['marketId']]=dict(sport='racing',mkt='WIN',ev=m['event']['name'],start=datetime.datetime.fromisoformat(m['marketStartTime'].replace('Z','+00:00')),names={r['selectionId']:r['runnerName'] for r in m['runners']})
        for m in api(tok,'listMarketCatalogue',{"filter":{"eventTypeIds":["1"],"marketTypeCodes":["MATCH_ODDS","OVER_UNDER_25"],"inPlayOnly":True},"marketProjection":["EVENT","RUNNER_DESCRIPTION","MARKET_START_TIME","MARKET_DESCRIPTION"],"maxResults":200}):
            mt=m.get('description',{}).get('marketType') or ('MATCH_ODDS' if 'Match Odds' in m.get('marketName','') else 'OVER_UNDER_25')
            out[m['marketId']]=dict(sport='football',mkt='MO' if mt=='MATCH_ODDS' else 'OU25',ev=m['event']['name'],start=datetime.datetime.fromisoformat(m['marketStartTime'].replace('Z','+00:00')),names={r['selectionId']:r['runnerName'] for r in m['runners']})
        for m in api(tok,'listMarketCatalogue',{"filter":{"eventTypeIds":["2"],"marketTypeCodes":["MATCH_ODDS"],"inPlayOnly":True},"marketProjection":["EVENT","RUNNER_DESCRIPTION","MARKET_START_TIME"],"maxResults":40,"sort":"MAXIMUM_TRADED"}):
            out[m['marketId']]=dict(sport='tennis',mkt='MO',ev=m['event']['name'],start=datetime.datetime.fromisoformat(m['marketStartTime'].replace('Z','+00:00')),names={r['selectionId']:r['runnerName'] for r in m['runners']})
        t2=(now+datetime.timedelta(hours=2)).strftime('%Y-%m-%dT%H:%M:%SZ'); t_now=now.strftime('%Y-%m-%dT%H:%M:%SZ')
        for m in api(tok,'listMarketCatalogue',{"filter":{"eventTypeIds":["1"],"marketTypeCodes":["MATCH_ODDS"],"inPlayOnly":False,"marketStartTime":{"from":t_now,"to":t2}},"marketProjection":["EVENT","RUNNER_DESCRIPTION","MARKET_START_TIME"],"maxResults":40,"sort":"MAXIMUM_TRADED"}):
            if m['marketId'] not in out: out[m['marketId']]=dict(sport='football',mkt='MO_PRE',ev=m['event']['name'],start=datetime.datetime.fromisoformat(m['marketStartTime'].replace('Z','+00:00')),names={r['selectionId']:r['runnerName'] for r in m['runners']})
```
### /root/pe-stream/stream_client.py def connect (line 15)
```python
def connect_db():
    c=psycopg2.connect(DB,sslmode='require'); c.autocommit=True; return c
con=connect_db(); cur=con.cursor()
cur.execute("""CREATE TABLE IF NOT EXISTS stream_ticks (ts_recv TIMESTAMPTZ, pt TIMESTAMPTZ, latency_ms INT, market_id TEXT, sport TEXT, mkt TEXT, sel_id BIGINT, sel TEXT,
  back_px NUMERIC, back_sz NUMERIC, lay_px NUMERIC, lay_sz NUMERIC, back2_px NUMERIC, lay2_px NUMERIC, ltp NUMERIC, tv NUMERIC, inplay BOOLEAN, status TEXT, secs_to_off INT);
CREATE INDEX IF NOT EXISTS stream_ticks_mkt ON stream_ticks (market_id, ts_recv);
CREATE TABLE IF NOT EXISTS stream_heartbeat (id INT PRIMARY KEY, last_seen TIMESTAMPTZ, markets INT, ticks_last_min INT, median_latency_ms INT, conn_state TEXT)""")
# ---------------- market universe (polled, cheap) ----------------
universe={}   # market_id -> meta
def _passed_types():
    try:
        import psycopg2 as _pg, sys as _sy; _sy.path.insert(0,'/root/pe-queue/runner'); import creds as _cr
        c=_pg.connect(_cr.pg_local(),sslmode='disable').cursor(); c.execute("SELECT DISTINCT market_type FROM fair_price_passed WHERE sport='Soccer'"); return sorted({t for (t,) in c.fetchall()}|{'MATCH_ODDS'})
    except Exception as e: print("passed types read failed",repr(e)[:80],flush=True); return ['MATCH_ODDS']
def refresh_universe(tok):
    now=datetime.datetime.now(datetime.timezone.utc); out={}
    t0=(now-datetime.timedelta(minutes=5)).strftime('%Y-%m-%dT%H:%M:%SZ'); t1=(now+datetime.timedelta(minutes=12)).strftime('%Y-%m-%dT%H:%M:%SZ')
    try:
        for m in api(tok,'listMarketCatalogue',{"filter":{"eventTypeIds":["7"],"marketTypeCodes":["WIN"],"marketCountries":["GB","IE"],"marketStartTime":{"from":t0,"to":t1}},"marketProjection":["EVENT","RUNNER_DESCRIPTION","MARKET_START_TIME"],"maxResults":60}):
            out[m['marketId']]=dict(sport='racing',mkt='WIN',ev=m['event']['name'],start=datetime.datetime.fromisoformat(m['marketStartTime'].replace('Z','+00:00')),names={r['selectionId']:r['runnerName'] for r in m['runners']})
        for m in api(tok,'listMarketCatalogue',{"filter":{"eventTypeIds":["1"],"marketTypeCodes":["MATCH_ODDS","OVER_UNDER_25"],"inPlayOnly":True},"marketProjection":["EVENT","RUNNER_DESCRIPTION","MARKET_START_TIME","MARKET_DESCRIPTION"],"maxResults":200}):
            mt=m.get('description',{}).get('marketType') or ('MATCH_ODDS' if 'Match Odds' in m.get('marketName','') else 'OVER_UNDER_25')
            out[m['marketId']]=dict(sport='football',mkt='MO' if mt=='MATCH_ODDS' else 'OU25',ev=m['event']['name'],start=datetime.datetime.fromisoformat(m['marketStartTime'].replace('Z','+00:00')),names={r['selectionId']:r['runnerName'] for r in m['runners']})
        for m in api(tok,'listMarketCatalogue',{"filter":{"eventTypeIds":["2"],"marketTypeCodes":["MATCH_ODDS"],"inPlayOnly":True},"marketProjection":["EVENT","RUNNER_DESCRIPTION","MARKET_START_TIME"],"maxResults":40,"sort":"MAXIMUM_TRADED"}):
            out[m['marketId']]=dict(sport='tennis',mkt='MO',ev=m['event']['name'],start=datetime.datetime.fromisoformat(m['marketStartTime'].replace('Z','+00:00')),names={r['selectionId']:r['runnerName'] for r in m['runners']})
        t2=(now+datetime.timedelta(hours=2)).strftime('%Y-%m-%dT%H:%M:%SZ'); t_now=now.strftime('%Y-%m-%dT%H:%M:%SZ')
        for m in api(tok,'listMarketCatalogue',{"filter":{"eventTypeIds":["1"],"marketTypeCodes":["MATCH_ODDS"],"inPlayOnly":False,"marketStartTime":{"from":t_now,"to":t2}},"marketProjection":["EVENT","RUNNER_DESCRIPTION","MARKET_START_TIME"],"maxResults":40,"sort":"MAXIMUM_TRADED"}):
            if m['marketId'] not in out: out[m['marketId']]=dict(sport='football',mkt='MO_PRE',ev=m['event']['name'],start=datetime.datetime.fromisoformat(m['marketStartTime'].replace('Z','+00:00')),names={r['selectionId']:r['runnerName'] for r in m['runners']})
    except Exception as e: print("catalogue",repr(e)[:150],flush=True)
    # 548: pre-off football of every passed-cell market type, next 2 hours — the tape the replay and the bot share
    try:
```
### bot login/api
```python
class _ReCur:
    def __init__(self): self._c=L.cursor()
    def execute(self,*a,**k):
        global L
        try: return self._c.execute(*a,**k)
        except (psycopg2.InterfaceError, psycopg2.OperationalError) as e:
            log(f"db connection lost ({str(e)[:60]}) - reconnecting"); L=psycopg2.connect(creds.pg_local()); L.autocommit=True; self._c=L.cursor(); return self._c.execute(*a,**k)
    def __getattr__(self,n): return getattr(self._c,n)
lc=_ReCur()
lc.execute("ALTER TABLE bookie_paper ADD COLUMN IF NOT EXISTS exchange TEXT DEFAULT 'betfair'; ALTER TABLE bookie_paper ADD COLUMN IF NOT EXISTS bf_market_id TEXT; ALTER TABLE bookie_paper ADD COLUMN IF NOT EXISTS start_ts TIMESTAMPTZ; ALTER TABLE bookie_paper ADD COLUMN IF NOT EXISTS fair NUMERIC")
APP,USER,PW=***); SSO=None; SSO_T=0
def login():
    global SSO,SSO_T
```
