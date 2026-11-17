# 646 — 2026-11-17 14:06 UTC
```python
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
            s.settimeout(30); last_msg=time.time()
            while True:
                ids=set(universe.keys())
                if ids and (ids!=state['sub_ids'] or time.time()-last_sub>600):
                    send({"op":"marketSubscription","id":2,"marketFilter":{"marketIds":sorted(ids)[:200]},"marketDataFilter":{"fields":["EX_BEST_OFFERS_DISP","EX_LTP","EX_TRADED_VOL","EX_MARKET_DEF"],"ladderLevels":3},"conflateMs":0,"heartbeatMs":5000})
                    state['sub_ids']=set(ids); last_sub=time.time(); print("subscribed",len(ids),"markets",flush=True)
                try: line=f.readline()
                except socket.timeout:
                    if time.time()-last_msg>90: raise ConnectionError('no message from Betfair for 90 s')
                    continue
                last_msg=time.time()
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
```
```
stream error JSONDecodeError('Expecting value: line 1 column 1 (char 0)') -> retry in 60
stream error JSONDecodeError('Expecting value: line 1 column 1 (char 0)') -> retry in 60
stream error JSONDecodeError('Expecting value: line 1 column 1 (char 0)') -> retry in 60
stream error JSONDecodeError('Expecting value: line 1 column 1 (char 0)') -> retry in 60
stream error JSONDecodeError('Expecting value: line 1 column 1 (char 0)') -> retry in 60
stream error JSONDecodeError('Expecting value: line 1 column 1 (char 0)') -> retry in 60
stream error JSONDecodeError('Expecting value: line 1 column 1 (char 0)') -> retry in 60
stream error JSONDecodeError('Expecting value: line 1 column 1 (char 0)') -> retry in 60
stream error JSONDecodeError('Expecting value: line 1 column 1 (char 0)') -> retry in 60
stream error JSONDecodeError('Expecting value: line 1 column 1 (char 0)') -> retry in 60
stream error JSONDecodeError('Expecting value: line 1 column 1 (char 0)') -> retry in 60
stream error JSONDecodeError('Expecting value: line 1 column 1 (char 0)') -> retry in 60
stream error JSONDecodeError('Expecting value: line 1 column 1 (char 0)') -> retry in 60
stream error JSONDecodeError('Expecting value: line 1 column 1 (char 0)') -> retry in 60
stream error JSONDecodeError('Expecting value: line 1 column 1 (char 0)') -> retry in 60
stream error JSONDecodeError('Expecting value: line 1 column 1 (char 0)') -> retry in 60
stream error JSONDecodeError('Expecting value: line 1 column 1 (char 0)') -> retry in 60
stream error JSONDecodeError('Expecting value: line 1 column 1 (char 0)') -> retry in 60
stream error JSONDecodeError('Expecting value: line 1 column 1 (char 0)') -> retry in 60
stream error JSONDecodeError('Expecting value: line 1 column 1 (char 0)') -> retry in 60
stream error JSONDecodeError('Expecting value: line 1 column 1 (char 0)') -> retry in 60
stream error JSONDecodeError('Expecting value: line 1 column 1 (char 0)') -> retry in 60
stream error JSONDecodeError('Expecting value: line 1 column 1 (char 0)') -> retry in 60
stream error JSONDecodeError('Expecting value: line 1 column 1 (char 0)') -> retry in 60
stream error JSONDecodeError('Expecting value: line 1 column 1 (char 0)') -> retry in 60
stream error JSONDecodeError('Expecting value: line 1 column 1 (char 0)') -> retry in 60
stream error JSONDecodeError('Expecting value: line 1 column 1 (char 0)') -> retry in 60
stream error JSONDecodeError('Expecting value: line 1 column 1 (char 0)') -> retry in 60
stream error JSONDecodeError('Expecting value: line 1 column 1 (char 0)') -> retry in 60
stream error JSONDecodeError('Expecting value: line 1 column 1 (char 0)') -> retry in 60
stream error JSONDecodeError('Expecting value: line 1 column 1 (char 0)') -> retry in 60
stream error JSONDecodeError('Expecting value: line 1 column 1 (char 0)') -> retry in 60
stream: {"op":"connection","connectionId":"210-171126090835-2626"}
```
liq recorder log in the gap:
```
```
