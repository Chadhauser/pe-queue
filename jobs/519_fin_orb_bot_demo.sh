#!/bin/bash
# 519: ORB-QQQ execution bot on Tradovate DEMO (MNQ). Signal = the verified rule on live Alpaca QQQ 1-min bars (09:30-09:35 ET
# range, direction of the 5-min candle, entry at 09:35 open, stop at range edge, target 10R, flat 15:59 ET). Size: $100 risk per
# trade (MNQ $2/pt), min 1 contract. Orders: one market entry + OSO bracket (stop + limit), isAutomated=true. Demo only —
# TRADOVATE_ENV=demo hard-wired to demo.tradovateapi.com; the bot refuses to start against live. Runs 09:25-16:05 ET weekdays
# via cron, logs every action to /root/pe-fin/bot/orb_mnq.log and trades to /root/pe-fin/bot/bot_trades.json (scoreboard reads it).
# First run tonight = auth + account + contract lookup only (markets shut), result printed to the queue log.
mkdir -p /root/pe-fin/bot && cd /root/pe-fin/bot || exit 1
cat > orb_mnq_bot.py <<'PY'
import os, sys, json, time, datetime as dt, requests, math, traceback
sys.path.insert(0,'/root/pe-queue/runner'); import creds
E=creds.all_vars(); U,P=E.get('TRADOVATE_USER'),E.get('TRADOVATE_PASS'); ENV=E.get('TRADOVATE_ENV','demo')
CID=E.get('TRADOVATE_CID','0'); SEC=E.get('TRADOVATE_SEC',''); AK,AS=E.get('ALPACA_KEY'),E.get('ALPACA_SECRET')
if ENV!='demo': print("REFUSING: TRADOVATE_ENV is not demo"); sys.exit(2)
BASE='https://demo.tradovateapi.com/v1'; LOG='/root/pe-fin/bot/orb_mnq.log'; TR='/root/pe-fin/bot/bot_trades.json'
RISK_USD=100.0; PT_VALUE=2.0; TICK=0.25
import zoneinfo; NY=zoneinfo.ZoneInfo('America/New_York')
def log(m):
    line=f"{dt.datetime.now(NY):%Y-%m-%d %H:%M:%S} {m}"; print(line,flush=True)
    with open(LOG,'a') as f: f.write(line+"\n")
def jl(p,d):
    try: return json.load(open(p))
    except Exception: return d
# ---------- Tradovate ----------
S=requests.Session(); TOK={}
def auth():
    body={'name':U,'password':P,'appId':'PEorb','appVersion':'1.0','cid':int(CID) if str(CID).isdigit() else 0,'sec':SEC,'deviceId':'pe-contabo-1'}
    r=S.post(f"{BASE}/auth/accesstokenrequest",json=body,timeout=30); j=r.json() if r.content else {}
    if r.status_code!=200 or 'accessToken' not in j: log(f"AUTH FAILED {r.status_code} {str(j)[:300]}"); return False
    TOK['t']=j['accessToken']; TOK['exp']=j.get('expirationTime'); S.headers['Authorization']=f"Bearer {TOK['t']}"; log("auth ok"); return True
def get(path,**p):
    r=S.get(f"{BASE}/{path}",params=p,timeout=30); r.raise_for_status(); return r.json()
def post(path,body):
    r=S.post(f"{BASE}/{path}",json=body,timeout=30)
    try: j=r.json()
    except Exception: j=r.text
    if r.status_code!=200: log(f"POST {path} -> {r.status_code} {str(j)[:300]}")
    return j
def account():
    a=get('account/list'); a=[x for x in a if x.get('active',True)]
    if not a: log("NO ACCOUNT"); return None
    return a[0]
def front_month():
    d=dt.datetime.now(NY).date(); codes={3:'H',6:'M',9:'U',12:'Z'}
    for y in (d.year,d.year+1):
        for m in (3,6,9,12):
            # 3rd Friday of contract month; roll 8 days before it
            f=dt.date(y,m,15); f+=dt.timedelta(days=(4-f.weekday())%7)
            if d<=f-dt.timedelta(days=8): return f"MNQ{codes[m]}{y%10}"
def contract(sym):
    c=get('contract/find',name=sym); return c
# ---------- signal from Alpaca QQQ ----------
AH={'APCA-API-KEY-ID':AK,'APCA-API-SECRET-KEY':AS}
def qqq_bars(start,end):
    r=requests.get('https://data.alpaca.markets/v2/stocks/bars',params={'symbols':'QQQ','timeframe':'1Min','start':start,'end':end,'feed':'iex','limit':100},headers=AH,timeout=30)
    return (r.json().get('bars') or {}).get('QQQ') or []
def mnq_last(cid):
    """MNQ last price: Tradovate market data is websocket-only, so take NQ=F (same price) from Yahoo, which the box already uses."""
    try:
        import yfinance as yf; p=yf.Ticker('NQ=F').fast_info['last_price']; return float(p) if p and p>1000 else None
    except Exception as e: log(f"NQ quote failed {repr(e)[:80]}"); return None
def run_day():
    today=dt.datetime.now(NY).date(); trades=jl(TR,[])
    if any(t['date']==str(today) for t in trades): log("already traded today"); return
    if not auth(): return
    acc=account()
    if not acc: return
    sym=front_month(); c=contract(sym); cid=c.get('id'); log(f"account {acc['name']} id {acc['id']} | contract {sym} id {cid}")
    # wait for 09:35:05 ET
    t_sig=dt.datetime.combine(today,dt.time(9,35,5),tzinfo=NY)
    while dt.datetime.now(NY)<t_sig: time.sleep(1)
    s=dt.datetime.combine(today,dt.time(9,30),tzinfo=NY); e=dt.datetime.combine(today,dt.time(9,35),tzinfo=NY)
    bars=[];
    for a in range(6):
        bars=qqq_bars(s.isoformat(),e.isoformat());
        if len(bars)>=4: break
        time.sleep(5)
    if len(bars)<3: log(f"NO SIGNAL: only {len(bars)} QQQ bars"); return
    o=bars[0]['o']; cl=bars[-1]['c']; hi=max(b['h'] for b in bars); lo=min(b['l'] for b in bars); rng=hi-lo
    if rng<=0 or abs(cl-o)<0.05*rng: log(f"NO TRADE: doji open o {o} c {cl} range {rng:.2f}"); trades.append(dict(date=str(today),note='no signal')); json.dump(trades,open(TR,'w'),indent=1); return
    side=1 if cl>o else -1; stop_q=lo if side>0 else hi; entry_q=cl
    R_q=abs(entry_q-stop_q)
    if R_q<=0 or (side>0 and stop_q>=entry_q) or (side<0 and stop_q<=entry_q): log("NO TRADE: stop on wrong side"); return
    # map QQQ points to MNQ points by price ratio using the last MNQ price (quote endpoint) or a fixed ratio fallback
    px=mnq_last(cid) or float(E.get('MNQ_QQQ_RATIO','36.5'))*entry_q
    ratio=px/entry_q; R_m=max(TICK,round(R_q*ratio/TICK)*TICK)
    qty=max(1,int(RISK_USD//(R_m*PT_VALUE)))
    action='Buy' if side>0 else 'Sell'; opp='Sell' if side>0 else 'Buy'
    stop_m=round((px-side*R_m)/TICK)*TICK; tgt_m=round((px+side*10*R_m)/TICK)*TICK
    body={'accountSpec':acc['name'],'accountId':acc['id'],'action':action,'symbol':sym,'orderQty':qty,'orderType':'Market','isAutomated':True,
          'bracket1':{'action':opp,'orderType':'Stop','stopPrice':stop_m},'bracket2':{'action':opp,'orderType':'Limit','price':tgt_m}}
    log(f"ENTRY {action} {qty}x{sym} ~{px} | QQQ o {o} c {cl} range {lo}-{hi} | R {R_m} pts (${R_m*PT_VALUE*qty:.0f} risk) stop {stop_m} target {tgt_m}")
    res=post('order/placeOSO',body); log(f"placeOSO -> {str(res)[:300]}")
    rec=dict(date=str(today),side=action,qty=qty,symbol=sym,ref_px=px,R_pts=R_m,stop=stop_m,target=tgt_m,order=str(res)[:200],risk_usd=R_m*PT_VALUE*qty)
    trades.append(rec); json.dump(trades,open(TR,'w'),indent=1)
    # flat at 15:59 ET
    t_flat=dt.datetime.combine(today,dt.time(15,59),tzinfo=NY)
    while dt.datetime.now(NY)<t_flat:
        time.sleep(30)
        if TOK.get('exp') and dt.datetime.now(dt.timezone.utc)>dt.datetime.fromisoformat(TOK['exp'].replace('Z','+00:00'))-dt.timedelta(minutes=10): auth()
    try:
        pos=get('position/list'); open_pos=[p for p in pos if p.get('contractId')==cid and p.get('netPos',0)!=0]
        if open_pos:
            log(f"FLAT at close: liquidating {open_pos[0].get('netPos')}"); log(str(post('order/liquidatePosition',{'accountId':acc['id'],'contractId':cid,'admin':False}))[:200])
        else: log("already flat (stop or target hit)")
        for o_ in get('order/list'):
            if o_.get('accountId')==acc['id'] and o_.get('ordStatus') in ('Working','Suspended'): post('order/cancelorder',{'orderId':o_['id']})
    except Exception: log(traceback.format_exc()[-400:])
    # record fills
    try:
        fills=[f for f in get('fill/list') if f.get('contractId')==cid and str(f.get('timestamp',''))[:10]==str(today)]
        rec['fills']=[dict(action=f.get('action'),qty=f.get('qty'),price=f.get('price'),ts=f.get('timestamp')) for f in fills]
        buys=sum(f['qty']*f['price'] for f in rec['fills'] if f['action']=='Buy'); sells=sum(f['qty']*f['price'] for f in rec['fills'] if f['action']=='Sell')
        rec['pnl_usd']=round((sells-buys)*PT_VALUE,2) if rec['fills'] else None
        json.dump(trades,open(TR,'w'),indent=1); log(f"DAY DONE pnl ${rec['pnl_usd']}")
    except Exception: log(traceback.format_exc()[-400:])
if __name__=='__main__':
    if '--check' in sys.argv:
        ok=auth();
        if ok:
            acc=account(); sym=front_month();
            try: c=contract(sym); print("CHECK OK account",acc and acc.get('name'),"contract",sym,c.get('id'))
            except Exception as e: print("CHECK contract lookup failed",repr(e)[:200])
        sys.exit(0 if ok else 1)
    try: run_day()
    except Exception: log(traceback.format_exc()[-800:])
PY
python3 -m py_compile orb_mnq_bot.py || exit 1
( crontab -l 2>/dev/null | grep -v orb_mnq_bot.py; echo "25 9 * * 1-5 cd /root/pe-fin/bot && TZ=America/New_York /usr/bin/python3 orb_mnq_bot.py >> cron.log 2>&1" ) | crontab -
# NOTE: cron hour above is interpreted in the box's local TZ by cron itself; fix by using the UTC equivalent (09:25 ET = 14:25 UTC in winter, 13:25 UTC in summer). Use 13:25 UTC and let the bot sleep until 09:35:05 ET.
( crontab -l 2>/dev/null | grep -v orb_mnq_bot.py; echo "25 13 * * 1-5 cd /root/pe-fin/bot && /usr/bin/python3 orb_mnq_bot.py >> cron.log 2>&1" ) | crontab -
echo "[]" > bot_trades.json.seed; [ -f bot_trades.json ] || cp bot_trades.json.seed bot_trades.json
python3 - <<'PY'
s=open('/root/pe-fin/team/fin_team.py').read()
if 'bot_trades' not in s:
    s=s.replace("""    L+=["","## Queue"]""","""    bt=jload('/root/pe-fin/bot/bot_trades.json',[])
    if bt:
        done=[t for t in bt if t.get('pnl_usd') is not None]; L+=["",f"## Bot — Tradovate DEMO, ORB on MNQ, $100 risk — {len(done)} days, ${sum(t['pnl_usd'] for t in done):+.2f}","","| date | side | qty | R pts | stop | target | pnl $ |","|---|---|---|---|---|---|---|"]
        for t in bt[-15:]: L.append(f"| {t.get('date')} | {t.get('side',t.get('note'))} | {t.get('qty','')} | {t.get('R_pts','')} | {t.get('stop','')} | {t.get('target','')} | {t.get('pnl_usd','')} |")
    L+=["","## Queue"]""")
    open('/root/pe-fin/team/fin_team.py','w').write(s); print("scoreboard: bot section added")
PY
python3 -m py_compile /root/pe-fin/team/fin_team.py || exit 1
python3 orb_mnq_bot.py --check
