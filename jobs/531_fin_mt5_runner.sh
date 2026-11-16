#!/bin/bash
# 531: Saturday-build item 3/4c — the MT5 strategy runner: ORB-QQQ and M7b (the two verified QQQ edges) traded on the broker's
# Nasdaq-100 CFD through the bridge. Signals from Alpaca QQQ bars; sizes from the portfolio lab's conservative rows (0.5% risk
# ORB, 1x notional M7b; ORB_RISK / M7_LEV on the box override). Sizing maths checked with worked examples: £10k, 0.5% risk, 130-pt
# stop, £1/pt/lot -> 0.38 lots PASS; same with 0.1 lot steps -> 0.3 (rounds DOWN, never over-risks) PASS; £2k account -> 0 lots,
# trade skipped PASS; M7b £10k x1 at 25,000 -> 0.4 lots PASS. Does nothing unless the bridge heartbeat is fresh (i.e. demo login live).
cd /root/pe-fin/team || exit 1
cat > mt5_runner.py <<'PY'
# MT5 STRATEGY RUNNER — the two verified QQQ edges, traded on the broker's Nasdaq-100 CFD through the bridge (demo first).
# ORB: 09:30-09:35 ET range on QQQ (Alpaca bars) -> direction, stop at the range edge, target 10R, flat 15:58 ET. Risk ORB_RISK of equity.
# M7b: QQQ moved >=1.5% from 09:30 to 15:00 ET -> same direction at 15:00, flat 15:58. Notional = M7_LEV x equity.
# Sizing from the portfolio lab (526); defaults are the conservative fixed rows (0.5% risk ORB, 1x M7b) until demo fills confirm costs.
# QQQ prices are mapped to the CFD by ratio at entry (both track the Nasdaq-100). Dormant unless the bridge heartbeat is fresh.
import sys, os, json, time, math, datetime as dt, zoneinfo, requests, traceback
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-fin/team'); import creds, mt5_client as B
E=creds.all_vars(); NY=zoneinfo.ZoneInfo('America/New_York'); H={'APCA-API-KEY-ID':E.get('ALPACA_KEY',''),'APCA-API-SECRET-KEY':E.get('ALPACA_SECRET','')}
ORB_RISK=float(E.get('ORB_RISK','0.005')); M7_LEV=float(E.get('M7_LEV','1.0')); LOG='/root/pe-fin/mt5/runner.log'; TR='/root/pe-fin/mt5/runner_trades.json'
def log(m):
    l=f"{dt.datetime.now(NY):%Y-%m-%d %H:%M:%S} {m}"; print(l,flush=True); open(LOG,'a').write(l+"\n")
def jl(p,d):
    try: return json.load(open(p))
    except Exception: return d
def qqq(start,end):
    r=requests.get('https://data.alpaca.markets/v2/stocks/bars',params={'symbols':'QQQ','timeframe':'1Min','start':start.isoformat(),'end':end.isoformat(),'feed':'iex','limit':1000},headers=H,timeout=30)
    return (r.json().get('bars') or {}).get('QQQ') or []
def find_symbol():
    s=E.get('MT5_NDX_SYMBOL')
    if s: return s
    for pat in ('*NDX*','*US100*','*USTEC*','*NAS100*','*NQ*'):
        r=B.call(dict(action='symbols',pattern=pat))
        if r.get('ok') and r.get('symbols'): return r['symbols'][0]['name']
    return None
def lots_for_risk(equity,risk_frac,stop_pts,tick_value,tick_size,vol_min,vol_step):
    """lots so that a stop of stop_pts index points loses risk_frac*equity. value of 1 point for 1 lot = tick_value/tick_size."""
    per_pt=tick_value/tick_size if tick_size else 0
    if per_pt<=0 or stop_pts<=0: return 0.0
    raw=risk_frac*equity/(stop_pts*per_pt); lots=math.floor(raw/vol_step)*vol_step
    return round(lots,8) if lots>=vol_min else 0.0
def lots_for_notional(equity,lev,price,contract,vol_min,vol_step):
    raw=lev*equity/(price*contract) if price and contract else 0; lots=math.floor(raw/vol_step)*vol_step
    return round(lots,8) if lots>=vol_min else 0.0
def wait_until(t):
    while dt.datetime.now(NY)<t: time.sleep(1)
def run_day():
    today=dt.datetime.now(NY).date()
    if today.weekday()>4: return
    if not B.alive(): log("bridge not alive: no trading today"); return
    hb=B.heartbeat(); eq=float(hb['equity']); sym=find_symbol()
    if not sym: log("no Nasdaq-100 symbol found on this account"); return
    info=[x for x in B.call(dict(action='symbols',pattern=sym))['symbols'] if x['name']==sym][0]
    trades=jl(TR,[]); rec=dict(date=str(today),symbol=sym,equity=eq,legs=[])
    # ---- ORB ----
    wait_until(dt.datetime.combine(today,dt.time(9,35,5),tzinfo=NY))
    b=qqq(dt.datetime.combine(today,dt.time(9,30),tzinfo=NY),dt.datetime.combine(today,dt.time(9,35),tzinfo=NY))
    if len(b)>=3:
        o,c=b[0]['o'],b[-1]['c']; hi=max(x['h'] for x in b); lo=min(x['l'] for x in b); rng=hi-lo
        if rng>0 and abs(c-o)>=0.05*rng:
            side='buy' if c>o else 'sell'; stop_q=lo if side=='buy' else hi; Rq=abs(c-stop_q)
            if Rq>0 and ((side=='buy' and stop_q<c) or (side=='sell' and stop_q>c)):
                q=B.call(dict(action='quote',symbol=sym)); px=q['ask'] if side=='buy' else q['bid']; ratio=px/c; stop_pts=Rq*ratio
                lots=lots_for_risk(eq,ORB_RISK,stop_pts,info['tick_value'],info['tick_size'],info['vol_min'],info['vol_step'])
                if lots>0:
                    sgn=1 if side=='buy' else -1
                    r=B.call(dict(action='open',symbol=sym,side=side,volume=lots,sl=px-sgn*stop_pts,tp=px+sgn*10*stop_pts,tag='ORB'))
                    rec['legs'].append(dict(leg='ORB',side=side,lots=lots,px=px,stop_pts=round(stop_pts,2),res=r)); log(f"ORB {side} {lots} {sym} @{px} stop {stop_pts:.1f}pts -> {r.get('ok')} {r.get('retcode','')}")
                else: log("ORB: size below minimum lot at this risk — skipped")
        else: log("ORB: no signal (doji open)")
    else: log(f"ORB: only {len(b)} QQQ bars")
    # ---- M7b ----
    wait_until(dt.datetime.combine(today,dt.time(15,0,5),tzinfo=NY))
    o=qqq(dt.datetime.combine(today,dt.time(9,30),tzinfo=NY),dt.datetime.combine(today,dt.time(9,31),tzinfo=NY))
    n=qqq(dt.datetime.combine(today,dt.time(14,59),tzinfo=NY),dt.datetime.combine(today,dt.time(15,0),tzinfo=NY))
    if o and n:
        mv=n[-1]['c']/o[0]['o']-1
        if abs(mv)>=0.015:
            side='buy' if mv>0 else 'sell'; q=B.call(dict(action='quote',symbol=sym)); px=q['ask'] if side=='buy' else q['bid']
            lots=lots_for_notional(eq,M7_LEV,px,info['contract'],info['vol_min'],info['vol_step'])
            if lots>0:
                r=B.call(dict(action='open',symbol=sym,side=side,volume=lots,tag='M7b')); rec['legs'].append(dict(leg='M7b',side=side,lots=lots,px=px,move=round(mv,4),res=r)); log(f"M7b {side} {lots} @{px} (QQQ {mv:+.2%}) -> {r.get('ok')}")
        else: log(f"M7b: QQQ {mv:+.2%} by 15:00, below 1.5% — no trade")
    # ---- flat ----
    wait_until(dt.datetime.combine(today,dt.time(15,58),tzinfo=NY))
    for tag in ('ORB','M7b'): B.call(dict(action='close_tag',tag=tag))
    time.sleep(5); rec['equity_close']=(B.heartbeat() or {}).get('equity'); rec['pnl']=round((rec['equity_close'] or eq)-eq,2) if rec['equity_close'] else None
    trades.append(rec); json.dump(trades,open(TR,'w'),indent=1); log(f"DAY DONE equity {eq} -> {rec['equity_close']} pnl {rec['pnl']}")
if __name__=='__main__':
    try: run_day()
    except Exception: log(traceback.format_exc()[-600:])
PY
python3 -m py_compile mt5_runner.py || exit 1
( crontab -l 2>/dev/null | grep -v mt5_runner.py; echo "20 13 * * 1-5 cd /root/pe-fin/team && /usr/bin/python3 mt5_runner.py >> /root/pe-fin/mt5/runner_cron.log 2>&1" ) | crontab -
echo "runner scheduled (dormant until the bridge is alive)"
