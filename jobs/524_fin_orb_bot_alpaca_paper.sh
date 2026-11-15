#!/bin/bash
# 524: Tradovate's API is a $25/month add-on that REQUIRES A FUNDED LIVE ACCOUNT (seen in Peter's settings, 15 Nov) — a demo can't
# be driven by a bot. So the test bed moves to Alpaca PAPER (free, keys already on the box): same ORB-QQQ rule, QQQ shares,
# $100 risk per trade (possible here: shares size to the stop), bracket order (stop at the range edge, target 10R), flat 15:58 ET.
# Hard-wired to paper-api.alpaca.markets: it cannot reach the live endpoint. Replaces the Tradovate bot's cron. Trades land in
# /root/pe-fin/bot/bot_trades.json -> the scoreboard's Bot section.
mkdir -p /root/pe-fin/bot && cd /root/pe-fin/bot || exit 1
( crontab -l 2>/dev/null | grep -v orb_mnq_bot.py ) | crontab -
cat > orb_alpaca_bot.py <<'PY'
import os, sys, json, time, math, datetime as dt, requests, traceback, zoneinfo
sys.path.insert(0,'/root/pe-queue/runner'); import creds
E=creds.all_vars(); K,S=E.get('ALPACA_KEY'),E.get('ALPACA_SECRET')
T='https://paper-api.alpaca.markets/v2'   # PAPER ONLY. Never api.alpaca.markets.
H={'APCA-API-KEY-ID':K,'APCA-API-SECRET-KEY':S}; LOG='/root/pe-fin/bot/orb_alpaca.log'; TR='/root/pe-fin/bot/bot_trades.json'
RISK_USD=100.0; NY=zoneinfo.ZoneInfo('America/New_York'); SYM='QQQ'
def log(m):
    line=f"{dt.datetime.now(NY):%Y-%m-%d %H:%M:%S} {m}"; print(line,flush=True); open(LOG,'a').write(line+"\n")
def jl(p,d):
    try: return json.load(open(p))
    except Exception: return d
def api(method,path,**kw):
    r=requests.request(method,f"{T}{path}",headers=H,timeout=30,**kw)
    try: j=r.json()
    except Exception: j=r.text
    if r.status_code>=300: log(f"{method} {path} -> {r.status_code} {str(j)[:200]}")
    return r.status_code,j
def bars(start,end):
    r=requests.get('https://data.alpaca.markets/v2/stocks/bars',params={'symbols':SYM,'timeframe':'1Min','start':start,'end':end,'feed':'iex','limit':100},headers=H,timeout=30)
    return (r.json().get('bars') or {}).get(SYM) or []
def check():
    sc,acc=api('GET','/account')
    if sc!=200: print("CHECK FAILED: paper endpoint rejected the keys (are these paper keys?)",sc,str(acc)[:150]); return False
    print("CHECK OK paper account",acc.get('account_number'),"equity",acc.get('equity'),"status",acc.get('status')); return True
def run_day():
    today=dt.datetime.now(NY).date(); trades=jl(TR,[])
    if any(t.get('date')==str(today) for t in trades): log("already traded today"); return
    sc,acc=api('GET','/account')
    if sc!=200: log("paper account unreachable, no trade"); return
    sc,clk=api('GET','/clock')
    if sc==200 and not clk.get('is_open'): log("market closed today"); trades.append(dict(date=str(today),note='market closed')); json.dump(trades,open(TR,'w'),indent=1); return
    t_sig=dt.datetime.combine(today,dt.time(9,35,5),tzinfo=NY)
    while dt.datetime.now(NY)<t_sig: time.sleep(1)
    s=dt.datetime.combine(today,dt.time(9,30),tzinfo=NY); e=dt.datetime.combine(today,dt.time(9,35),tzinfo=NY); b=[]
    for a in range(6):
        b=bars(s.isoformat(),e.isoformat())
        if len(b)>=4: break
        time.sleep(5)
    if len(b)<3: log(f"NO SIGNAL: only {len(b)} bars"); trades.append(dict(date=str(today),note=f'only {len(b)} bars')); json.dump(trades,open(TR,'w'),indent=1); return
    o=b[0]['o']; c=b[-1]['c']; hi=max(x['h'] for x in b); lo=min(x['l'] for x in b); rng=hi-lo
    if rng<=0 or abs(c-o)<0.05*rng: log(f"NO TRADE doji o {o} c {c} rng {rng:.2f}"); trades.append(dict(date=str(today),note='no signal (doji open)')); json.dump(trades,open(TR,'w'),indent=1); return
    side=1 if c>o else -1; stop=lo if side>0 else hi; R=abs(c-stop)
    if R<=0 or (side>0 and stop>=c) or (side<0 and stop<=c): log("NO TRADE stop on wrong side"); trades.append(dict(date=str(today),note='gap: stop wrong side')); json.dump(trades,open(TR,'w'),indent=1); return
    qty=max(1,int(RISK_USD//R)); tgt=round(c+side*10*R,2); stp=round(stop,2)
    order={'symbol':SYM,'qty':str(qty),'side':'buy' if side>0 else 'sell','type':'market','time_in_force':'day','order_class':'bracket',
           'take_profit':{'limit_price':str(tgt)},'stop_loss':{'stop_price':str(stp)}}
    log(f"ENTRY {order['side']} {qty} {SYM} ~{c} | range {lo}-{hi} | R {R:.2f} (${R*qty:.0f} risk) stop {stp} target {tgt}")
    sc,res=api('POST','/orders',json=order); rec=dict(date=str(today),side=order['side'],qty=qty,symbol=SYM,ref_px=c,R_pts=round(R,2),stop=stp,target=tgt,risk_usd=round(R*qty,2),order_id=res.get('id') if isinstance(res,dict) else None,order_status=sc)
    trades.append(rec); json.dump(trades,open(TR,'w'),indent=1)
    if sc>=300: return
    t_flat=dt.datetime.combine(today,dt.time(15,58),tzinfo=NY)
    while dt.datetime.now(NY)<t_flat: time.sleep(30)
    api('DELETE','/orders'); sc,pos=api('GET',f'/positions/{SYM}')
    if sc==200 and float(pos.get('qty',0))!=0: log(f"FLAT at close: closing {pos.get('qty')}"); api('DELETE',f'/positions/{SYM}')
    else: log("already flat (stop or target hit)")
    time.sleep(20)
    sc,orders=api('GET','/orders',params={'status':'closed','after':dt.datetime.combine(today,dt.time(9,0),tzinfo=NY).isoformat(),'limit':50,'nested':'true'})
    fills=[]
    def walk(os_):
        for o_ in os_:
            if o_.get('filled_qty') and float(o_['filled_qty'])>0: fills.append(dict(side=o_['side'],qty=float(o_['filled_qty']),price=float(o_['filled_avg_price'] or 0),at=o_.get('filled_at')))
            walk(o_.get('legs') or [])
    if sc==200: walk(orders)
    buys=sum(f['qty']*f['price'] for f in fills if f['side']=='buy'); sells=sum(f['qty']*f['price'] for f in fills if f['side']=='sell')
    rec['fills']=fills; rec['pnl_usd']=round(sells-buys,2) if fills else None; json.dump(trades,open(TR,'w'),indent=1); log(f"DAY DONE pnl ${rec['pnl_usd']}")
if __name__=='__main__':
    if '--check' in sys.argv: sys.exit(0 if check() else 1)
    try: run_day()
    except Exception: log(traceback.format_exc()[-800:])
PY
python3 -m py_compile orb_alpaca_bot.py || exit 1
( crontab -l 2>/dev/null | grep -v orb_alpaca_bot.py; echo "25 13 * * 1-5 cd /root/pe-fin/bot && /usr/bin/python3 orb_alpaca_bot.py >> cron.log 2>&1" ) | crontab -
sed -i 's/Tradovate DEMO, ORB on MNQ/Alpaca PAPER, ORB on QQQ shares/' /root/pe-fin/team/fin_team.py 2>/dev/null; python3 -m py_compile /root/pe-fin/team/fin_team.py
sed -i 's#tail -15 /root/pe-fin/bot/orb_mnq.log#tail -15 /root/pe-fin/bot/orb_alpaca.log#; s#python3 orb_mnq_bot.py --check#python3 orb_alpaca_bot.py --check#' /root/pe-fin/team/diag.sh 2>/dev/null
python3 orb_alpaca_bot.py --check | tee check.txt
