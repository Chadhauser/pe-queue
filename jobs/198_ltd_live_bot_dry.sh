#!/bin/bash
# 198: IN-PLAY LAY-THE-DRAW — LIVE BOT, INSTALLED IN DRY-RUN. Same rule as the paper bot (194) but working from Betfair's live book
# so it can place real orders: 0-0 at 46'/60'/75', draw lay 1.5-2.5, >= £20 at the lay price, >= £5k matched, both sides >= 1.30.
# Entry: LAY the draw at the best lay price, stake from ltd_control (default £2 -> liability <= £3). Exit: on the next goal (draw
# price reopen), 120 s later BACK the draw for the greening stake (lay_stake x lay_px / back_px); if no goal, the lay settles at the
# close. Controls in ltd_control: enabled, stake, dry_run (TRUE now — logs every order it would place, places none), max_open 5,
# max_daily_loss £15. The gate to flip dry_run=false: 50 settled paper trades across 194 + this bot's dry log, positive total, no
# trigger negative. Goal detection for exits: a draw price jump >= 25% between two consecutive book reads while the market was
# suspended/reopened, or a liq_goal_depth row. Tables: ltd_live_trades, ltd_live_heartbeat.
mkdir -p /root/pe-ltd && cat > /root/pe-ltd/ltd_live.py <<'PYFILE'
import os, sys, time, json, datetime, requests, psycopg2, psycopg2.extras
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
cur.execute("""CREATE TABLE IF NOT EXISTS ltd_control (id INT PRIMARY KEY, enabled BOOLEAN, stake NUMERIC, max_daily_loss NUMERIC, max_open INT, dry_run BOOLEAN, note TEXT);
INSERT INTO ltd_control VALUES (1,true,2.00,15.00,5,true,'installed dry-run 25 Oct 2026; flip dry_run=false at the paper gate') ON CONFLICT (id) DO NOTHING;
CREATE TABLE IF NOT EXISTS ltd_live_trades (id SERIAL PRIMARY KEY, market_id TEXT, event_name TEXT, competition TEXT, draw_sel_id BIGINT, trig INT, minute INT, entered_at TIMESTAMPTZ,
  lay_req NUMERIC, lay_matched NUMERIC, lay_size NUMERIC, lay_bet_id TEXT, dry BOOLEAN, goal_at TIMESTAMPTZ, exit_due TIMESTAMPTZ, back_req NUMERIC, back_matched NUMERIC, back_size NUMERIC, back_bet_id TEXT,
  exited_at TIMESTAMPTZ, exit_reason TEXT, pnl NUMERIC, status TEXT, note TEXT, UNIQUE (market_id, trig));
CREATE TABLE IF NOT EXISTS ltd_live_heartbeat (id INT PRIMARY KEY, last_seen TIMESTAMPTZ, open_positions INT, today_pnl NUMERIC, dry BOOLEAN)""")
def ctl():
    cur.execute("SELECT * FROM ltd_control WHERE id=1"); return cur.fetchone()
def place(market_id,sel_id,side,size,price,dry):
    if dry: return {'status':'DRY','betId':None,'averagePriceMatched':price,'sizeMatched':size}
    res=api('placeOrders',{"marketId":market_id,"instructions":[{"selectionId":sel_id,"side":side,"orderType":"LIMIT","limitOrder":{"size":round(size,2),"price":price,"persistenceType":"PERSIST" if side=='LAY' else "LAPSE"}}]})
    rep=(res.get('instructionReports') or [{}])[0]
    return {'status':rep.get('orderStatus') or res.get('status'),'betId':rep.get('betId'),'averagePriceMatched':rep.get('averagePriceMatched'),'sizeMatched':rep.get('sizeMatched'),'raw':json.dumps(res)[:300]}
def hedge_size(lay_size,lay_px,back_px): return round(lay_size*lay_px/back_px,2)
def pnl_hedged(lay_size,lay_px,back_size,back_px):
    # lay L at p: if draw wins -L(p-1), else +L. back B at q: if draw wins +B(q-1), else -B. Greened both ways:
    if_draw=-lay_size*(lay_px-1)+back_size*(back_px-1); if_not=lay_size-back_size
    p=min(if_draw,if_not); return round(p*(1-COMM) if p>0 else p,2)
def minute_of(start,now):
    el=(now-start).total_seconds()/60
    if el>60: el-=15
    return int(el)
open_tr={}; last_cat=0; cat={}; last_hb=0; dstate={}
while True:
    try:
        c=ctl(); now=datetime.datetime.now(datetime.timezone.utc)
        if time.time()-last_cat>60:
            ms=api('listMarketCatalogue',{"filter":{"eventTypeIds":["1"],"marketTypeCodes":["MATCH_ODDS"],"inPlayOnly":True},"marketProjection":["EVENT","COMPETITION","RUNNER_DESCRIPTION","MARKET_START_TIME"],"maxResults":200})
            cat={m['marketId']:dict(ev=m['event']['name'],comp=(m.get('competition') or {}).get('name',''),start=datetime.datetime.fromisoformat(m['marketStartTime'].replace('Z','+00:00')),
                 draw=next((r['selectionId'] for r in m['runners'] if 'draw' in r['runnerName'].lower()),None)) for m in ms}
            last_cat=time.time()
        ids=[m for m in cat if cat[m]['draw']]
        books={}
        for i in range(0,len(ids),25):
            for b in api('listMarketBook',{"marketIds":ids[i:i+25],"priceProjection":{"priceData":["EX_BEST_OFFERS"]}}): books[b['marketId']]=b
        cur.execute("SELECT coalesce(sum(pnl),0) p FROM ltd_live_trades WHERE exited_at::date=current_date"); today=float(cur.fetchone()['p'])
        for mid,b in books.items():
            meta=cat[mid]; minute=minute_of(meta['start'],now); tm=b.get('totalMatched') or 0
            rs={r['selectionId']:r for r in b.get('runners',[])}; dr=rs.get(meta['draw'])
            if not dr: continue
            ex=dr.get('ex',{}); bk=ex.get('availableToBack',[]); ly=ex.get('availableToLay',[]); ltp=dr.get('lastPriceTraded')
            others=[r.get('lastPriceTraded') for s,r in rs.items() if s!=meta['draw'] and r.get('lastPriceTraded')]
            # goal detection from the draw's own price path (jump >= 25% between reads) or a suspension that reopens higher
            prev=dstate.get(mid); dstate[mid]=(ltp,b.get('status'),now)
            goal_now = prev is not None and ltp and prev[0] and (ltp>=prev[0]*1.25)
            key=mid
            # ---- manage open position
            if key in open_tr:
                t=open_tr[key]
                if t['goal_at'] is None and goal_now:
                    t['goal_at']=now; cur.execute("UPDATE ltd_live_trades SET goal_at=%s, exit_due=%s WHERE id=%s",(now,now+datetime.timedelta(seconds=120),t['id'])); print(f"GOAL seen {meta['ev']} draw {prev[0]}->{ltp}",flush=True)
                if t['goal_at'] is not None and now>=t['goal_at']+datetime.timedelta(seconds=120) and bk:
                    bp=bk[0]['price']; bs=hedge_size(t['lay_size'],t['lay_px'],bp)
                    r=place(mid,meta['draw'],'BACK',bs,bp,c['dry_run']); pnl=pnl_hedged(t['lay_size'],t['lay_px'],float(r.get('sizeMatched') or bs),float(r.get('averagePriceMatched') or bp))
                    cur.execute("UPDATE ltd_live_trades SET back_req=%s, back_matched=%s, back_size=%s, back_bet_id=%s, exited_at=%s, exit_reason='GOAL', pnl=%s, status='CLOSED' WHERE id=%s",(bp,r.get('averagePriceMatched'),bs,r.get('betId'),now,pnl,t['id']))
                    print(f"EXIT {meta['ev']} lay {t['lay_px']} -> back {bp} = {pnl:+.2f} {'(dry)' if c['dry_run'] else ''}",flush=True); open_tr.pop(key)
                elif b.get('status')=='CLOSED' or minute>=97:
                    # settle: draw won if its price collapsed
                    won=(ltp is not None and ltp<=1.1)
                    pnl=round((-t['lay_size']*(t['lay_px']-1)) if won else t['lay_size']*(1-COMM),2)
                    cur.execute("UPDATE ltd_live_trades SET exited_at=%s, exit_reason=%s, pnl=%s, status='CLOSED' WHERE id=%s",(now,'SETTLE_LOSS' if won else 'SETTLE_WIN',pnl,t['id'])); open_tr.pop(key)
                continue
            # ---- entry
            if not c['enabled'] or today<=-float(c['max_daily_loss']) or len(open_tr)>=int(c['max_open']): continue
            trig=46 if 46<=minute<=48 else (60 if 60<=minute<=62 else (75 if 75<=minute<=77 else None))
            if trig is None or not ly or not bk or b.get('inplay') is not True or b.get('status')!='OPEN': continue
            lp,lsz=ly[0]['price'],ly[0]['size']
            if not (1.5<=lp<=2.5) or lsz<20 or tm<5000 or len(others)<2 or min(others)<1.30: continue
            cur.execute("SELECT 1 FROM ltd_live_trades WHERE market_id=%s AND trig=%s",(mid,trig))
            if cur.fetchone(): continue
            cur.execute("SELECT 1 FROM liq_goal_depth WHERE market_id=%s AND mkt='MO' LIMIT 1",(mid,))
            if cur.fetchone(): continue                      # a goal already happened
            stake=float(c['stake']); r=place(mid,meta['draw'],'LAY',stake,lp,c['dry_run'])
            cur.execute("""INSERT INTO ltd_live_trades (market_id,event_name,competition,draw_sel_id,trig,minute,entered_at,lay_req,lay_matched,lay_size,lay_bet_id,dry,status)
                           VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,'OPEN') ON CONFLICT DO NOTHING RETURNING id""",(mid,meta['ev'],meta['comp'],meta['draw'],trig,minute,now,lp,r.get('averagePriceMatched'),stake,r.get('betId'),c['dry_run']))
            row=cur.fetchone()
            if row: open_tr[key]={'id':row['id'],'lay_px':float(r.get('averagePriceMatched') or lp),'lay_size':stake,'goal_at':None}; print(f"LAY DRAW {meta['ev']} [{meta['comp']}] {minute}' @ {lp} x £{stake} {'(dry)' if c['dry_run'] else 'LIVE'}",flush=True)
        if time.time()-last_hb>60:
            cur.execute("INSERT INTO ltd_live_heartbeat VALUES (1,now(),%s,%s,%s) ON CONFLICT (id) DO UPDATE SET last_seen=now(), open_positions=EXCLUDED.open_positions, today_pnl=EXCLUDED.today_pnl, dry=EXCLUDED.dry",(len(open_tr),today,c['dry_run'])); last_hb=time.time()
        time.sleep(15)
    except Exception as e:
        print("loop",repr(e)[:200],flush=True); time.sleep(20)
        try: con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        except Exception: pass
PYFILE
python3 -m py_compile /root/pe-ltd/ltd_live.py || exit 1
python3 - <<'PY'
src=open('/root/pe-ltd/ltd_live.py').read(); i=src.index("def hedge_size"); j=src.index("def minute_of"); ns={'COMM':0.02}; exec(src[i:j],ns)
hs=ns['hedge_size'](2.0,2.0,5.0); p=ns['pnl_hedged'](2.0,2.0,hs,5.0); print("lay £2 @2.0, goal, back",hs,"@5.0 -> pnl",p,"(expected +1.18 greened)")
assert abs(hs-0.8)<0.01 and abs(p-1.18)<0.02
p2=ns['pnl_hedged'](2.0,2.0,ns['hedge_size'](2.0,2.0,1.5),1.5); print("adverse: back @1.5 -> pnl",p2); assert p2<0
print("hedge maths PASS")
PY
cat > /root/pe-ltd/keepalive_live.sh <<'SH'
#!/bin/bash
pgrep -f ltd_live.py >/dev/null || (cd /root/pe-ltd && nohup python3 ltd_live.py >> ltd_live.log 2>&1 &)
SH
chmod +x /root/pe-ltd/keepalive_live.sh
( crontab -l 2>/dev/null | grep -v keepalive_live ; echo "* * * * * /root/pe-ltd/keepalive_live.sh" ) | crontab -
/root/pe-ltd/keepalive_live.sh; sleep 50; pgrep -af ltd_live.py | head -1; tail -5 /root/pe-ltd/ltd_live.log
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require').cursor(); c.execute("SELECT * FROM ltd_control"); print("control:",c.fetchall()); c.execute("SELECT * FROM ltd_live_heartbeat"); print("heartbeat:",c.fetchall())
PY
