#!/bin/bash
# 220: LATE LAY-OVER — REAL-ORDER BOT, INSTALLED IN DRY-RUN (same pattern as 198). Works from Betfair's own Over/Under 2.5 book so its log
# is the execution-realistic twin of the paper bot: 70'-85', ESPN score <= 1 goal (matched through the Match Odds market the recorder
# tracks for the same event), Over best lay 2.2-12 with >= £10, price-must-agree-with-score guard. LAY £2 (lo_control.stake). Exit:
# Over best back falls 30%+ between two sane reads = goal -> 120 s later BACK the greening stake; else at 90' BACK at best back if a sane
# book exists; else settle at close (Over back <= 1.15 = lost). dry_run=true: logs every order it would place, places none. Flip
# (UPDATE lo_control SET dry_run=false) only at the paper gate: 60 settled, positive, each minute band >= 0.
mkdir -p /root/pe-xg && cat > /root/pe-xg/late_over_live.py <<'PYFILE'
import sys, time, json, datetime, requests, psycopg2, psycopg2.extras
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
sys.path.insert(0,'/root/pe-queue/runner'); import creds
APP_KEY,USER,PW=creds.betfair()
if not (APP_KEY and USER and PW): sys.exit("no betfair creds")
TOK=None; TOK_T=0; COMM=0.02
def login():
    global TOK,TOK_T
    r=requests.post("https://identitysso.betfair.com/api/login",data={"username":USER,"password":PW},headers={"X-Application":APP_KEY,"Accept":"application/json"},timeout=15).json()
    if r.get('status')!='SUCCESS': raise SystemExit("LOGIN FAILED "+str(r))
    TOK=r['token']; TOK_T=time.time()
def api(ep,payload):
    if TOK is None or time.time()-TOK_T>3000: login()
    r=requests.post(f"https://api.betfair.com/exchange/betting/rest/v1.0/{ep}/",json=payload,headers={"X-Authentication":TOK,"X-Application":APP_KEY,"Content-Type":"application/json","Accept":"application/json"},timeout=20)
    if r.status_code!=200: print("API",ep,r.status_code,r.text[:200],flush=True); r.raise_for_status()
    return r.json()
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
cur.execute("""CREATE TABLE IF NOT EXISTS lo_control (id INT PRIMARY KEY, enabled BOOLEAN, stake NUMERIC, max_daily_loss NUMERIC, max_open INT, dry_run BOOLEAN, note TEXT);
INSERT INTO lo_control VALUES (1,true,2.00,15.00,6,true,'installed dry-run 25 Oct 2026; flip dry_run=false at the paper gate (60 settled, positive, each minute band >= 0)') ON CONFLICT (id) DO NOTHING;
CREATE TABLE IF NOT EXISTS lo_live_trades (id SERIAL PRIMARY KEY, market_id TEXT UNIQUE, event_name TEXT, competition TEXT, over_sel_id BIGINT, minute INT, goals INT, entered_at TIMESTAMPTZ,
  lay_req NUMERIC, lay_matched NUMERIC, lay_size NUMERIC, lay_bet_id TEXT, dry BOOLEAN, goal_at TIMESTAMPTZ, back_req NUMERIC, back_matched NUMERIC, back_size NUMERIC, back_bet_id TEXT,
  exited_at TIMESTAMPTZ, exit_reason TEXT, pnl NUMERIC, status TEXT, note TEXT);
CREATE TABLE IF NOT EXISTS lo_live_heartbeat (id INT PRIMARY KEY, last_seen TIMESTAMPTZ, inplay_markets INT, open_positions INT, today_pnl NUMERIC, dry BOOLEAN)""")
def ctl():
    cur.execute("SELECT * FROM lo_control WHERE id=1"); return cur.fetchone()
def place(market_id,sel_id,side,size,price,dry):
    if dry: return {'status':'DRY','betId':None,'averagePriceMatched':price,'sizeMatched':size}
    res=api('placeOrders',{"marketId":market_id,"instructions":[{"selectionId":sel_id,"side":side,"orderType":"LIMIT","limitOrder":{"size":round(size,2),"price":price,"persistenceType":"PERSIST" if side=='LAY' else "LAPSE"}}]})
    rep=(res.get('instructionReports') or [{}])[0]
    return {'status':rep.get('orderStatus') or res.get('status'),'betId':rep.get('betId'),'averagePriceMatched':rep.get('averagePriceMatched'),'sizeMatched':rep.get('sizeMatched')}
def hedge_size(lay_size,lay_px,back_px): return round(lay_size*lay_px/back_px,2)
def pnl_hedged(lay_size,lay_px,back_size,back_px):
    if_over=-lay_size*(lay_px-1)+back_size*(back_px-1); if_not=lay_size-back_size
    p=min(if_over,if_not); return round(p*(1-COMM) if p>0 else p,2)
def minute_of(start,now):
    el=(now-start).total_seconds()/60
    if el>60: el-=15
    return int(el)
def espn_goals(ev):
    cur.execute("SELECT market_id FROM liq_sample WHERE event_name=%s AND mkt='MO' AND ts>now()-interval '4 hours' ORDER BY ts DESC LIMIT 1",(ev,)); r=cur.fetchone()
    if not r: return None
    cur.execute('SELECT hs, "as" FROM espn_stats WHERE market_id=%s AND hs IS NOT NULL AND ts>now()-interval \'4 minutes\' ORDER BY ts DESC LIMIT 1',(r['market_id'],)); e=cur.fetchone()
    return (e['hs']+e['as']) if e else None
open_tr={}; last_cat=0; cat={}; last_hb=0; ostate={}; lastbook={}
while True:
    try:
        c=ctl(); now=datetime.datetime.now(datetime.timezone.utc)
        if time.time()-last_cat>60:
            ms=api('listMarketCatalogue',{"filter":{"eventTypeIds":["1"],"marketTypeCodes":["OVER_UNDER_25"],"inPlayOnly":True},"marketProjection":["EVENT","COMPETITION","RUNNER_DESCRIPTION","MARKET_START_TIME"],"maxResults":200})
            cat={m['marketId']:dict(ev=m['event']['name'],comp=(m.get('competition') or {}).get('name',''),start=datetime.datetime.fromisoformat(m['marketStartTime'].replace('Z','+00:00')),
                 over=next((r['selectionId'] for r in m['runners'] if r['runnerName'].lower().startswith('over')),None)) for m in ms}
            last_cat=time.time()
        ids=[m for m in cat if cat[m]['over']]; books={}
        for i in range(0,len(ids),25):
            for b in api('listMarketBook',{"marketIds":ids[i:i+25],"priceProjection":{"priceData":["EX_BEST_OFFERS"]}}): books[b['marketId']]=b
        cur.execute("SELECT coalesce(sum(pnl),0) p FROM lo_live_trades WHERE exited_at::date=current_date"); today=float(cur.fetchone()['p'])
        for mid,b in books.items():
            meta=cat[mid]; minute=minute_of(meta['start'],now)
            rs={r['selectionId']:r for r in b.get('runners',[])}; ov=rs.get(meta['over'])
            if not ov: continue
            ex=ov.get('ex',{}); bk=ex.get('availableToBack',[]); ly=ex.get('availableToLay',[])
            obk=bk[0]['price'] if bk else None; oly=ly[0]['price'] if ly else None; sane=obk is not None and oly is not None and oly<=obk*1.2
            prev=ostate.get(mid)
            if sane: ostate[mid]=(obk,oly,now); lastbook[mid]=obk
            goal_now = sane and prev is not None and obk<=prev[0]*0.7
            if mid in open_tr:
                t=open_tr[mid]
                if t['goal_at'] is None and goal_now:
                    t['goal_at']=now; cur.execute("UPDATE lo_live_trades SET goal_at=%s WHERE id=%s",(now,t['id'])); print(f"GOAL seen {meta['ev']} over {prev[0]}->{obk}",flush=True)
                due = (t['goal_at'] is not None and now>=t['goal_at']+datetime.timedelta(seconds=120)) or (minute>=90)
                if due and sane and b.get('status')=='OPEN':
                    bs=hedge_size(t['lay_size'],t['lay_px'],obk); r=place(mid,meta['over'],'BACK',bs,obk,c['dry_run'])
                    pnl=pnl_hedged(t['lay_size'],t['lay_px'],float(r.get('sizeMatched') or bs),float(r.get('averagePriceMatched') or obk))
                    cur.execute("UPDATE lo_live_trades SET back_req=%s, back_matched=%s, back_size=%s, back_bet_id=%s, exited_at=%s, exit_reason=%s, pnl=%s, status='CLOSED' WHERE id=%s",(obk,r.get('averagePriceMatched'),bs,r.get('betId'),now,'GOAL' if t['goal_at'] else 'M90',pnl,t['id']))
                    print(f"EXIT {meta['ev']} lay {t['lay_px']} -> back {obk} = {pnl:+.2f} {'(dry)' if c['dry_run'] else ''}",flush=True); open_tr.pop(mid)
                elif b.get('status')=='CLOSED' or minute>=100:
                    fb=lastbook.get(mid)
                    if fb is None: reason,pnl='UNKNOWN',None
                    elif fb<=1.15: reason,pnl='SETTLE_LOSS',round(-t['lay_size']*(t['lay_px']-1),2)
                    elif fb>=5: reason,pnl='SETTLE_WIN',round(t['lay_size']*(1-COMM),2)
                    else: reason,pnl='UNKNOWN',None
                    cur.execute("UPDATE lo_live_trades SET exited_at=%s, exit_reason=%s, pnl=%s, status='CLOSED' WHERE id=%s",(now,reason,pnl,t['id'])); open_tr.pop(mid)
                continue
            if not c['enabled'] or today<=-float(c['max_daily_loss']) or len(open_tr)>=int(c['max_open']): continue
            if not (70<=minute<=85) or not sane or b.get('inplay') is not True or b.get('status')!='OPEN': continue
            if not (2.2<=oly<=12) or ly[0]['size']<10: continue
            cur.execute("SELECT 1 FROM lo_live_trades WHERE market_id=%s",(mid,))
            if cur.fetchone(): continue
            g=espn_goals(meta['ev'])
            if g is None or g>1 or (g==0 and oly<4.0) or (g==1 and oly<2.2): continue
            stake=float(c['stake']); r=place(mid,meta['over'],'LAY',stake,oly,c['dry_run'])
            cur.execute("""INSERT INTO lo_live_trades (market_id,event_name,competition,over_sel_id,minute,goals,entered_at,lay_req,lay_matched,lay_size,lay_bet_id,dry,status)
                           VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,'OPEN') ON CONFLICT DO NOTHING RETURNING id""",(mid,meta['ev'],meta['comp'],meta['over'],minute,g,now,oly,r.get('averagePriceMatched'),stake,r.get('betId'),c['dry_run']))
            row=cur.fetchone()
            if row: open_tr[mid]={'id':row['id'],'lay_px':float(r.get('averagePriceMatched') or oly),'lay_size':stake,'goal_at':None}; print(f"LAY OVER2.5 {meta['ev']} [{meta['comp']}] {minute}' goals {g} @ {oly} x £{stake} {'(dry)' if c['dry_run'] else 'LIVE'}",flush=True)
        if time.time()-last_hb>60:
            cur.execute("INSERT INTO lo_live_heartbeat VALUES (1,now(),%s,%s,%s,%s) ON CONFLICT (id) DO UPDATE SET last_seen=now(), inplay_markets=EXCLUDED.inplay_markets, open_positions=EXCLUDED.open_positions, today_pnl=EXCLUDED.today_pnl, dry=EXCLUDED.dry",(len(ids),len(open_tr),today,c['dry_run'])); last_hb=time.time()
        time.sleep(20)
    except Exception as e:
        print("loop",repr(e)[:200],flush=True); time.sleep(20)
        try: con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        except Exception: pass
PYFILE
python3 -m py_compile /root/pe-xg/late_over_live.py || exit 1
python3 - <<'PY'
src=open('/root/pe-xg/late_over_live.py').read(); i=src.index("def hedge_size"); j=src.index("def minute_of"); ns={'COMM':0.02}; exec(src[i:j],ns)
hs=ns['hedge_size'](2.0,4.0,8.0); p=ns['pnl_hedged'](2.0,4.0,hs,8.0); print("lay £2 @4.0, 90' back",hs,"@8.0 -> pnl",p); assert 0.9<p<1.0
p2=ns['pnl_hedged'](2.0,4.0,ns['hedge_size'](2.0,4.0,1.5),1.5); print("goal against: back @1.5 ->",p2); assert p2<0
print("hedge maths PASS")
PY
cat > /root/pe-xg/keepalive_lo_live.sh <<'SH'
#!/bin/bash
pgrep -f late_over_live.py >/dev/null || (cd /root/pe-xg && nohup python3 late_over_live.py >> late_over_live.log 2>&1 &)
SH
chmod +x /root/pe-xg/keepalive_lo_live.sh
( crontab -l 2>/dev/null | grep -v keepalive_lo_live ; echo "* * * * * /root/pe-xg/keepalive_lo_live.sh" ) | crontab -
/root/pe-xg/keepalive_lo_live.sh; sleep 50; pgrep -af late_over_live.py | head -1; tail -4 /root/pe-xg/late_over_live.log
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require').cursor(); c.execute("SELECT * FROM lo_control"); print("control:",c.fetchall()); c.execute("SELECT * FROM lo_live_heartbeat"); print("heartbeat:",c.fetchall())
PY
