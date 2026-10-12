#!/bin/bash
# 039: pg_bot fixes — Decimal*float crash in scoring-team detection (killed every loop iteration last night, no money moved);
# unmatched entries now retried at the new best lay within the 60-100s window instead of abandoned. Restart via cron keepalive.
mkdir -p /root/pe-pg && cat > /root/pe-pg/pg_bot.py <<'PYFILE'
import os, sys, time, json, datetime, requests, psycopg2, psycopg2.extras
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
sys.path.insert(0,'/root/pe-queue/runner'); import creds
APP_KEY,USER,PW=creds.betfair()
if not (APP_KEY and USER and PW): sys.exit("no betfair creds")
TOK=None; TOK_T=0
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
cur.execute("""CREATE TABLE IF NOT EXISTS pg_control (id INT PRIMARY KEY, enabled BOOLEAN, stake NUMERIC, max_daily_loss NUMERIC, max_open INT, dry_run BOOLEAN, note TEXT);
INSERT INTO pg_control (id,enabled,stake,max_daily_loss,max_open,dry_run,note) VALUES (1,true,2.00,30.00,6,false,'PG v2 live £2 from 12 Oct 2026 (Peter, 11 Oct)') ON CONFLICT (id) DO NOTHING;
CREATE TABLE IF NOT EXISTS pg_trades (id SERIAL PRIMARY KEY, goal_ts TIMESTAMPTZ, market_id TEXT, event_name TEXT, competition TEXT, mkt TEXT, sel TEXT, selection_id BIGINT, minute INT, goals_before INT,
  pre_ltp NUMERIC, entry_requested NUMERIC, entry_matched NUMERIC, entry_size NUMERIC, entry_bet_id TEXT, entered_at TIMESTAMPTZ, exit_due TIMESTAMPTZ, exit_reason TEXT, exit_requested NUMERIC, exit_matched NUMERIC, exit_bet_id TEXT, exited_at TIMESTAMPTZ, pnl NUMERIC, status TEXT, note TEXT);
CREATE TABLE IF NOT EXISTS pg_heartbeat (id INT PRIMARY KEY, last_seen TIMESTAMPTZ, open_positions INT, today_pnl NUMERIC)""")
def ctl():
    cur.execute("SELECT * FROM pg_control WHERE id=1"); return cur.fetchone()
def today_pnl():
    cur.execute("SELECT coalesce(sum(pnl),0) p FROM pg_trades WHERE exited_at::date=current_date"); return float(cur.fetchone()['p'])
def place(market_id,sel_id,side,size,price,dry):
    if dry: return {'status':'DRY','betId':None,'averagePriceMatched':price,'sizeMatched':size}
    res=api('placeOrders',{"marketId":market_id,"instructions":[{"selectionId":sel_id,"side":side,"orderType":"LIMIT","limitOrder":{"size":round(size,2),"price":price,"persistenceType":"LAPSE"}}]})
    rep=(res.get('instructionReports') or [{}])[0]
    return {'status':rep.get('orderStatus') or res.get('status'),'betId':rep.get('betId'),'averagePriceMatched':rep.get('averagePriceMatched'),'sizeMatched':rep.get('sizeMatched'),'raw':json.dumps(res)[:300]}
def cancel_unmatched(market_id,bet_id):
    try: api('cancelOrders',{"marketId":market_id,"instructions":[{"betId":bet_id}]})
    except Exception as e: print("cancel err",e,flush=True)
def book(market_id):
    b=api('listMarketBook',{"marketIds":[market_id],"priceProjection":{"priceData":["EX_BEST_OFFERS"]}})
    return b[0] if b else None
def best(bk,sel_id):
    for r in bk.get('runners',[]):
        if r['selectionId']==sel_id:
            ex=r.get('ex',{}); b=ex.get('availableToBack',[]); l=ex.get('availableToLay',[])
            return (b[0]['price'] if b else None,b[0]['size'] if b else 0,l[0]['price'] if l else None,l[0]['size'] if l else 0,r.get('lastPriceTraded'))
    return (None,0,None,0,None)
def runner_ids(market_id):
    c=api('listMarketCatalogue',{"filter":{"marketIds":[market_id]},"marketProjection":["RUNNER_DESCRIPTION","EVENT"],"maxResults":1})
    return ({r['runnerName']:r['selectionId'] for r in c[0]['runners']},c[0]['event']['name']) if c else ({},None)
seen=set(); cur.execute("SELECT DISTINCT market_id||'|'||goal_ts::text k FROM pg_trades"); seen|={r['k'] for r in cur.fetchall()}
pending={}   # (market_id,goal_ts) -> dict(due, meta)
print("pg_bot up",flush=True)
while True:
    try:
        c=ctl()
        # new goals from the recorder (offset 0 rows = reopen moment), last 3 minutes
        cur.execute("""SELECT market_id, event_name, competition, mkt, goal_ts, minute, min(pre_ltp) FILTER (WHERE sel='OVER') over_pre,
                       max(CASE WHEN sel='HOME' THEN pre_ltp END) home_pre, max(CASE WHEN sel='AWAY' THEN pre_ltp END) away_pre,
                       max(CASE WHEN sel='HOME' THEN ltp END) home_now, max(CASE WHEN sel='AWAY' THEN ltp END) away_now
                       FROM liq_goal_depth WHERE offset_s=0 AND goal_ts > now()-interval '3 minutes' GROUP BY 1,2,3,4,5,6""")
        for g in cur.fetchall():
            k=f"{g['market_id']}|{g['goal_ts']}"
            if k in seen: continue
            seen.add(k)
            if not c['enabled'] or today_pnl()<=-float(c['max_daily_loss']): print("disabled or daily loss hit; skipping",k,flush=True); continue
            mn=g['minute'] or 0
            if mn<5 or mn>80: continue
            # goals so far in this match today: count reopen events for this event (MO market) incl. this one
            cur.execute("SELECT count(DISTINCT goal_ts) n FROM liq_goal_depth WHERE event_name=%s AND mkt='MO' AND offset_s=0 AND goal_ts<=%s AND goal_ts>now()-interval '3 hours'",(g['event_name'],g['goal_ts']))
            goals=cur.fetchone()['n'] or 1
            if goals>2: continue
            cur.execute("SELECT count(*) n FROM pg_trades WHERE status='OPEN'");
            if cur.fetchone()['n']>=int(c['max_open']): print("max_open reached",flush=True); continue
            if g['mkt']=='OU25': sel='Over 2.5 Goals'; selkey='OVER'
            else:
                # scoring team = the one whose price SHORTENED
                if g['home_pre'] and g['home_now'] and g['away_pre'] and g['away_now']:
                    sel=None; selkey=None
                    hp,hn,ap,an=float(g['home_pre']),float(g['home_now']),float(g['away_pre']),float(g['away_now'])
                    if hn<hp*0.9: selkey='HOME'
                    elif an<ap*0.9: selkey='AWAY'
                    if not selkey: continue
                else: continue
            pending[k]={'due':g['goal_ts']+datetime.timedelta(seconds=60),'g':g,'selkey':selkey,'goals':goals}
        now=datetime.datetime.now(datetime.timezone.utc)
        # entries due
        for k,p in list(pending.items()):
            if now<p['due']: continue
            if now>p['due']+datetime.timedelta(seconds=40): pending.pop(k); continue   # missed the window, do not chase
            g=p['g']; ids,ev=runner_ids(g['market_id'])
            if not ids: pending.pop(k); continue
            if p['selkey']=='OVER': sel_id=ids.get('Over 2.5 Goals')
            else:
                h,a=(ev or g['event_name']).split(' v ')[0].strip(),(ev or g['event_name']).split(' v ')[-1].strip()
                sel_id=ids.get(h) if p['selkey']=='HOME' else ids.get(a)
            if not sel_id: pending.pop(k); continue
            bk=book(g['market_id'])
            if not bk or bk.get('status')!='OPEN': continue
            bp,bs,lp,ls,ltp=best(bk,sel_id)
            if not lp or lp<1.15 or lp>12: pending.pop(k); continue
            res=place(g['market_id'],sel_id,'LAY',float(c['stake']),lp,bool(c['dry_run']))
            matched=float(res.get('sizeMatched') or 0) if not c['dry_run'] else float(c['stake'])
            if res.get('status') not in ('EXECUTION_COMPLETE','DRY') or matched<=0:
                if res.get('betId'): cancel_unmatched(g['market_id'],res['betId'])
                if now<p['due']+datetime.timedelta(seconds=30): print("not matched at",lp,"- retrying",flush=True); continue   # retry at the new best lay within the window
                pending.pop(k)
                cur.execute("INSERT INTO pg_trades (goal_ts,market_id,event_name,competition,mkt,sel,selection_id,minute,goals_before,pre_ltp,entry_requested,entry_size,entry_bet_id,entered_at,status,note) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,now(),'UNMATCHED',%s)",
                            (g['goal_ts'],g['market_id'],g['event_name'],g['competition'],g['mkt'],p['selkey'],sel_id,g['minute'],p['goals'],g['over_pre'] if p['selkey']=='OVER' else (g['home_pre'] if p['selkey']=='HOME' else g['away_pre']),lp,c['stake'],res.get('betId'),str(res.get('raw') or res.get('status'))[:200]))
                print("UNMATCHED",g['event_name'],p['selkey'],lp,res.get('status'),flush=True); continue
            pending.pop(k,None)
            cur.execute("INSERT INTO pg_trades (goal_ts,market_id,event_name,competition,mkt,sel,selection_id,minute,goals_before,pre_ltp,entry_requested,entry_matched,entry_size,entry_bet_id,entered_at,exit_due,status) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,now(),now()+interval '10 minutes','OPEN')",
                        (g['goal_ts'],g['market_id'],g['event_name'],g['competition'],g['mkt'],p['selkey'],sel_id,g['minute'],p['goals'],g['over_pre'] if p['selkey']=='OVER' else (g['home_pre'] if p['selkey']=='HOME' else g['away_pre']),lp,res.get('averagePriceMatched') or lp,matched,res.get('betId')))
            print("ENTRY LAY",g['event_name'],p['selkey'],"@",res.get('averagePriceMatched') or lp,"size",matched,flush=True)
        # exits
        cur.execute("SELECT * FROM pg_trades WHERE status='OPEN'")
        for t in cur.fetchall():
            cur.execute("SELECT 1 FROM liq_goal_depth WHERE market_id=%s AND offset_s=0 AND goal_ts>%s LIMIT 1",(t['market_id'],t['entered_at']))
            new_goal=cur.fetchone() is not None
            if not new_goal and now<t['exit_due']: continue
            bk=book(t['market_id'])
            if not bk: continue
            if bk.get('status')!='OPEN':
                if bk.get('status')=='CLOSED':
                    cur.execute("UPDATE pg_trades SET status='SETTLED_BY_MARKET', exit_reason='market closed', exited_at=now() WHERE id=%s",(t['id'],))
                continue
            bp,bs,lp,ls,ltp=best(bk,t['selection_id'])
            if not bp: continue
            # equalised exit: back stake b = s*em/xm gives the same P&L whatever the result (Betfair minimum £2 applies)
            size=max(2.0,round(float(t['entry_size'])*float(t['entry_matched'])/float(bp),2))
            res=place(t['market_id'],t['selection_id'],'BACK',size,bp,bool(c['dry_run']))
            if res.get('status') not in ('EXECUTION_COMPLETE','DRY'):
                if res.get('betId'): cancel_unmatched(t['market_id'],res['betId'])
                # retry next loop at new price; after exit_due+3 min take whatever
                if now>t['exit_due']+datetime.timedelta(minutes=3):
                    cur.execute("UPDATE pg_trades SET note=coalesce(note,'')||' exit unmatched x' WHERE id=%s",(t['id'],))
                continue
            xm=float(res.get('averagePriceMatched') or bp); em=float(t['entry_matched']); s=float(t['entry_size'])
            pnl=s*(xm-em)/xm   # equalised green/red: lay s at em, back s*em/xm at xm
            pnl=round(pnl*(1-0.02),2) if pnl>0 else round(pnl,2)
            cur.execute("UPDATE pg_trades SET status='CLOSED', exit_reason=%s, exit_requested=%s, exit_matched=%s, exit_bet_id=%s, exited_at=now(), pnl=%s WHERE id=%s",
                        ('GOAL' if new_goal else 'CLOCK',bp,xm,res.get('betId'),pnl,t['id']))
            print("EXIT",t['event_name'],t['sel'],em,"->",xm,"pnl",pnl,'GOAL' if new_goal else 'CLOCK',flush=True)
        cur.execute("SELECT count(*) n FROM pg_trades WHERE status='OPEN'"); n_open=cur.fetchone()['n']
        cur.execute("INSERT INTO pg_heartbeat (id,last_seen,open_positions,today_pnl) VALUES (1,now(),%s,%s) ON CONFLICT (id) DO UPDATE SET last_seen=now(), open_positions=EXCLUDED.open_positions, today_pnl=EXCLUDED.today_pnl",(n_open,today_pnl()))
        time.sleep(3)
    except SystemExit: raise
    except Exception as e:
        print("loop error",repr(e)[:200],flush=True); time.sleep(8)
        try: con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        except Exception: pass
PYFILE
python3 -m py_compile /root/pe-pg/pg_bot.py || exit 1
pkill -f pg_bot.py; sleep 75; pgrep -af pg_bot.py || echo NOT RUNNING; tail -5 /root/pe-pg/bot.log
