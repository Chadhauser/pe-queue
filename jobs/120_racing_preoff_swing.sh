#!/bin/bash
# 120: PRE-OFF RACING TAPE + PAPER SWING BOT (Peter 21 Oct: "Why can't we automate that? put money in and lay it at the right
# price" — the automatable half of Caan Berry's pre-race trading). One daemon, own dir /root/pe-race, cron keepalive:
#  TAPE  — every UK/IRE horse racing WIN market from 10 min before the off to the off (and 60s after): 1s polling of the top 3 in
#          the market (by LTP) with best 3 levels each side + traded volume per runner -> racing_tape. Also the whole field at 1
#          row/runner/10s so field-wide moves are visible. Volume-weighted WOM per runner each second.
#  PAPER — racing_swing_paper: trigger = WOM >= 0.60 on one side for 20 consecutive seconds AND LTP has already moved >= 1 tick
#          that way inside the window (real money trading, not a wall). Steam (back money heavy): paper BACK one tick inside the
#          spread; drift (lay money heavy): paper LAY one tick inside. Fill rule = order counts as matched only when LTP later
#          trades AT OR THROUGH our price. Exit: +3 ticks (hedged, counted at the opposite touch), -3 ticks stop, or 20s before
#          the off — whichever first; never in-play. Max 1 open trade per market, max 2 per race, no entries inside -30s.
#          P&L per £10 stake, 2pct commission on wins. Betfair tick ladder respected.
#  Verdict after 3 racing days (Fri 24 Oct a.m.): positive both halves with >= 60 trades -> £2 live bot Mon 26 Oct.
mkdir -p /root/pe-race && cat > /root/pe-race/race_swing.py <<'PYFILE'
import os, sys, time, datetime, collections, math, requests, psycopg2, psycopg2.extras
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
sys.path.insert(0,'/root/pe-queue/runner'); import creds
APP_KEY,USER,PW=creds.betfair()
if not (APP_KEY and USER and PW): sys.exit("NO BETFAIR CREDENTIALS")
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
cur.execute("""CREATE TABLE IF NOT EXISTS racing_tape (ts TIMESTAMPTZ, market_id TEXT, venue TEXT, race TEXT, market_start TIMESTAMPTZ, secs_to_off INT, status TEXT,
  sel_id BIGINT, sel_name TEXT, rank INT, ltp NUMERIC, back_px NUMERIC, back_sz NUMERIC, lay_px NUMERIC, lay_sz NUMERIC, back3_sz NUMERIC, lay3_sz NUMERIC,
  wom NUMERIC, traded NUMERIC, total_matched NUMERIC);
CREATE INDEX IF NOT EXISTS racing_tape_mkt ON racing_tape (market_id, ts);
CREATE TABLE IF NOT EXISTS racing_swing_paper (id SERIAL PRIMARY KEY, market_id TEXT, venue TEXT, race TEXT, market_start TIMESTAMPTZ, sel_id BIGINT, sel_name TEXT, rank INT,
  side TEXT, signal_ts TIMESTAMPTZ, signal_secs_to_off INT, wom_at_signal NUMERIC, order_px NUMERIC, filled_ts TIMESTAMPTZ, exit_px NUMERIC, exit_ts TIMESTAMPTZ, exit_reason TEXT,
  ticks NUMERIC, pnl_per_10 NUMERIC, total_matched NUMERIC);
CREATE TABLE IF NOT EXISTS racing_heartbeat (id INT PRIMARY KEY, last_seen TIMESTAMPTZ, live_markets INT, open_trades INT, trades_today INT)""")
# Betfair tick ladder
LAD=[(1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)]
def tick(p):
    for lo,hi,s in LAD:
        if p<hi: return s
    return 10
def rnd(p):
    s=tick(p); return round(round(p/s)*s,2)
def up(p,n=1):
    for _ in range(n): p=rnd(p+tick(p)+1e-9)
    return p
def down(p,n=1):
    for _ in range(n): p=rnd(p-tick(p-1e-9)+1e-9) if p>1.01 else 1.01
    return p
def nticks(a,b):   # ticks from a to b (positive = b higher)
    n=0; p=a
    if b>a:
        while p<b-1e-9 and n<500: p=up(p); n+=1
        return n
    while p>b+1e-9 and n<500: p=down(p); n+=1
    return -n
WOM_T=0.60; WOM_SECS=20; TGT=3; STOP=3; LAST_ENTRY=30; FLAT_AT=20; STAKE=10.0; COMM=0.02
cat={}; last_cat=0; hist=collections.defaultdict(lambda: collections.deque(maxlen=60)); open_tr={}; per_mkt=collections.Counter(); last_full=collections.defaultdict(float); last_hb=0
def refresh():
    global cat,last_cat
    now=datetime.datetime.now(datetime.timezone.utc)
    try:
        res=api('listMarketCatalogue',{"filter":{"eventTypeIds":["7"],"marketTypeCodes":["WIN"],"marketCountries":["GB","IE"],
               "marketStartTime":{"from":(now-datetime.timedelta(minutes=2)).isoformat(),"to":(now+datetime.timedelta(minutes=12)).isoformat()}},
               "marketProjection":["EVENT","RUNNER_DESCRIPTION","MARKET_START_TIME"],"maxResults":50})
    except Exception as e: print("catalogue",repr(e)[:100],flush=True); return
    new={}
    for m in res:
        st=datetime.datetime.fromisoformat(m['marketStartTime'].replace('Z','+00:00'))
        new[m['marketId']]={'venue':m['event']['name'],'race':m.get('marketName',''),'start':st,'runners':{r['selectionId']:r['runnerName'] for r in m['runners']}}
    cat=new; last_cat=time.time()
def close(key,px,why,now,tm):
    t=open_tr.pop(key); e=t['px']
    tk=nticks(e,px) if t['side']=='BACK' else nticks(px,e)   # back wants price to fall -> negative ticks is good; normalise: positive = profit
    tk=-tk if t['side']=='BACK' else tk
    if t['side']=='BACK': pnl=(e/px-1)*STAKE
    else: pnl=(1-e/px)*STAKE
    if pnl>0: pnl*=(1-COMM)
    cur.execute("UPDATE racing_swing_paper SET exit_px=%s, exit_ts=%s, exit_reason=%s, ticks=%s, pnl_per_10=%s, total_matched=%s WHERE id=%s",(px,now,why,tk,round(pnl,3),tm,t['id']))
    print(f"CLOSE {t['side']} {t['name']} {e}->{px} {why} {pnl:+.2f}",flush=True)
while True:
    try:
        if time.time()-last_cat>60: refresh()
        now=datetime.datetime.now(datetime.timezone.utc)
        live=[mid for mid,m in cat.items() if -60<=(m['start']-now).total_seconds()<=600]
        if not live: time.sleep(5); continue
        mbs=[]
        for i in range(0,len(live),5):
            try: mbs+=api('listMarketBook',{"marketIds":live[i:i+5],"priceProjection":{"priceData":["EX_BEST_OFFERS","EX_TRADED"],"exBestOffersOverrides":{"bestPricesDepth":3}}})
            except Exception as e: print("book",repr(e)[:100],flush=True)
        rows=[]
        for mb in mbs:
            mid=mb['marketId']; meta=cat.get(mid)
            if not meta: continue
            sto=int((meta['start']-now).total_seconds()); inplay=mb.get('inplay'); st=mb.get('status'); tm=mb.get('totalMatched') or 0
            rs=[r for r in mb.get('runners',[]) if r.get('status')=='ACTIVE' and r.get('lastPriceTraded')]
            rs.sort(key=lambda r: r['lastPriceTraded']); full=(time.time()-last_full[mid]>=10)
            if full: last_full[mid]=time.time()
            for rank,r in enumerate(rs,1):
                ex=r.get('ex',{}); b=ex.get('availableToBack',[]); l=ex.get('availableToLay',[])
                b3=sum(x['size'] for x in b[:3]); l3=sum(x['size'] for x in l[:3]); wom=(b3/(b3+l3)) if (b3+l3)>0 else None
                traded=sum(x['size'] for x in ex.get('tradedVolume',[]))
                if rank<=3 or full:
                    rows.append((now,mid,meta['venue'],meta['race'],meta['start'],sto,st,r['selectionId'],meta['runners'].get(r['selectionId'],''),rank,r['lastPriceTraded'],
                                 (b[0]['price'] if b else None),(b[0]['size'] if b else None),(l[0]['price'] if l else None),(l[0]['size'] if l else None),b3,l3,wom,traded,tm))
                if rank>3 or not b or not l: continue
                key=(mid,r['selectionId']); h=hist[key]; h.append((time.time(),wom,r['lastPriceTraded'],b[0]['price'],l[0]['price']))
                # ---- manage open paper trade
                if key in open_tr:
                    t=open_tr[key]
                    if not t['filled']:
                        # fill when LTP trades at/through our price (back filled if ltp>=px ... we are asking a higher price than touch; lay filled if ltp<=px)
                        if (t['side']=='BACK' and r['lastPriceTraded']>=t['px']) or (t['side']=='LAY' and r['lastPriceTraded']<=t['px']):
                            t['filled']=True; cur.execute("UPDATE racing_swing_paper SET filled_ts=%s WHERE id=%s",(now,t['id']))
                        elif sto<=FLAT_AT or inplay or st!='OPEN' or time.time()-t['t0']>90:
                            open_tr.pop(key); cur.execute("UPDATE racing_swing_paper SET exit_reason='UNFILLED', pnl_per_10=0 WHERE id=%s",(t['id'],))
                        continue
                    e=t['px']
                    if t['side']=='BACK':   # exit by laying at the lay touch
                        x=l[0]['price']; tk=-nticks(e,x)
                    else:                    # exit by backing at the back touch
                        x=b[0]['price']; tk=nticks(e,x)
                    if tk>=TGT: close(key,x,'TARGET',now,tm)
                    elif tk<=-STOP: close(key,x,'STOP',now,tm)
                    elif sto<=FLAT_AT or inplay or st!='OPEN': close(key,x,'FLAT_PRE_OFF' if not inplay else 'INPLAY',now,tm)
                    continue
                # ---- signal
                if sto<LAST_ENTRY or sto>600 or st!='OPEN' or inplay or per_mkt[mid]>=2 or any(k[0]==mid for k in open_tr): continue
                win=[x for x in h if time.time()-x[0]<=WOM_SECS]
                if len(win)<WOM_SECS-5 or any(x[1] is None for x in win): continue
                woms=[x[1] for x in win]; p0=win[0][2]; p1=r['lastPriceTraded']
                side=None
                if min(woms)>=WOM_T and nticks(p0,p1)<=-1: side='BACK'       # back money heavy + already shortening -> steam: back it
                elif max(woms)<=1-WOM_T and nticks(p0,p1)>=1: side='LAY'      # lay money heavy + already drifting -> drift: lay it
                if not side: continue
                px=down(l[0]['price']) if side=='BACK' else up(b[0]['price'])   # one tick inside the spread
                if px<=b[0]['price'] and side=='BACK': px=b[0]['price']           # spread already 1 tick: join the touch
                if px>=l[0]['price'] and side=='LAY': px=l[0]['price']
                cur.execute("INSERT INTO racing_swing_paper (market_id,venue,race,market_start,sel_id,sel_name,rank,side,signal_ts,signal_secs_to_off,wom_at_signal,order_px,total_matched) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) RETURNING id",
                            (mid,meta['venue'],meta['race'],meta['start'],r['selectionId'],meta['runners'].get(r['selectionId'],''),rank,side,now,sto,round(sum(woms)/len(woms),3),px,tm))
                open_tr[key]={'id':cur.fetchone()[0],'side':side,'px':px,'filled':False,'t0':time.time(),'name':meta['runners'].get(r['selectionId'],'')}
                per_mkt[mid]+=1; print(f"SIGNAL {side} {meta['venue']} {meta['race']} {open_tr[key]['name']} @ {px} wom {woms[-1]:.2f} sto {sto}",flush=True)
        if rows: psycopg2.extras.execute_values(cur,"INSERT INTO racing_tape VALUES %s",rows)
        if time.time()-last_hb>30:
            cur.execute("INSERT INTO racing_heartbeat VALUES (1,now(),%s,%s,(SELECT count(*) FROM racing_swing_paper WHERE signal_ts::date=current_date)) ON CONFLICT (id) DO UPDATE SET last_seen=now(), live_markets=EXCLUDED.live_markets, open_trades=EXCLUDED.open_trades, trades_today=EXCLUDED.trades_today",(len(live),len(open_tr)))
            last_hb=time.time()
        time.sleep(max(0.2,1.0-(datetime.datetime.now(datetime.timezone.utc)-now).total_seconds()))
    except Exception as e:
        print("loop",repr(e)[:200],flush=True); time.sleep(5)
        try: con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
        except Exception: pass
PYFILE
python3 -m py_compile /root/pe-race/race_swing.py || exit 1
cat > /root/pe-race/keepalive.sh <<'SH'
#!/bin/bash
pgrep -f race_swing.py >/dev/null || (cd /root/pe-race && nohup python3 race_swing.py >> race.log 2>&1 &)
SH
chmod +x /root/pe-race/keepalive.sh
cat > /root/pe-race/retention.py <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require'); c.autocommit=True; cur=c.cursor(); cur.execute("DELETE FROM racing_tape WHERE ts<now()-interval '7 days'"); print("racing_tape pruned",cur.rowcount)
PY
( crontab -l 2>/dev/null | grep -v pe-race ; echo "* * * * * /root/pe-race/keepalive.sh" ; echo "35 4 * * * cd /root/pe-race && python3 retention.py >> race.log 2>&1" ) | crontab -
/root/pe-race/keepalive.sh; sleep 90; pgrep -af race_swing.py; tail -20 /root/pe-race/race.log
# tick-ladder self-test (the one piece of logic that must be right before any real stake)
python3 - <<'PY'
import importlib.util,sys
src=open('/root/pe-race/race_swing.py').read().split("WOM_T=")[0]
src=src[src.index("LAD="):]
ns={}; exec(src,ns)
up,down,nticks=ns['up'],ns['down'],ns['nticks']
tests=[(up(1.99),2.0),(up(2.0),2.02),(up(2.98),3.0),(up(3.0),3.05),(up(3.95),4.0),(up(4.0),4.1),(up(5.9),6.0),(up(6.0),6.2),(up(9.8),10.0),(up(10.0),10.5),(down(2.0),1.99),(down(3.0),2.98),(down(4.0),3.95),(down(6.0),5.9),(nticks(2.0,2.06),3),(nticks(3.0,2.98),-1),(nticks(5.0,5.3),3)]
for got,exp in tests: print("PASS" if abs(got-exp)<1e-9 else f"FAIL got {got}", "expected", exp)
PY
