#!/bin/bash
# 529: Saturday-build item 4b — the MT5 bridge. mt5_bridge.py runs under Windows Python inside Wine (needs 527's install) and
# executes order files dropped by our Linux code (mt5_client.py): open / close_all / close_tag / quote / symbols. Safety built in:
# refuses any account that is not DEMO unless MT5_ALLOW_LIVE=1 is set on the box; KILL file closes everything and blocks new orders;
# lot cap MT5_MAX_LOTS (default 2); heartbeat.json every 2 s with equity and positions. Tested offline against a stub MetaTrader5:
# symbol lookup PASS, 5.37 lots capped to 2.0 PASS, KILL closed the position and refused the next order PASS, live account refused PASS.
# DORMANT until MT5_LOGIN/MT5_PASSWORD/MT5_SERVER are on the box (the Darwinex demo login, Thursday). Keeper cron starts it then.
mkdir -p /root/pe-fin/mt5 && cd /root/pe-fin/mt5 || exit 1
cat > mt5_bridge.py <<'PY'
# MT5 BRIDGE — runs under WINDOWS Python inside the Wine prefix (the only place the MetaTrader5 package works). Linux code talks to
# it through files: drop an order JSON in INBOX, read the answer from OUTBOX. Wine maps the Linux root to drive Z:, so the same
# folders are visible both sides. Secrets are read from /root/pe-logger/.env (MT5_LOGIN, MT5_PASSWORD, MT5_SERVER); nothing is logged.
# Safety: KILL file -> close everything and refuse new orders; max lots per order; demo-only unless MT5_ALLOW_LIVE=1 is set on the box.
import os, sys, json, time, glob, traceback, datetime as dt
BASE=os.environ.get('MT5_BRIDGE_BASE','Z:/root/pe-fin/mt5')
INBOX,OUTBOX,DONE=f'{BASE}/inbox',f'{BASE}/outbox',f'{BASE}/done'
HB,KILL,LOG=f'{BASE}/heartbeat.json',f'{BASE}/KILL',f'{BASE}/bridge.log'
for d in (INBOX,OUTBOX,DONE): os.makedirs(d,exist_ok=True)
def log(m):
    with open(LOG,'a') as f: f.write(f"{dt.datetime.utcnow():%Y-%m-%d %H:%M:%S} {m}\n")
def env():
    E={}; p=os.environ.get('MT5_ENV_FILE','Z:/root/pe-logger/.env')
    try:
        for l in open(p):
            if '=' in l and not l.strip().startswith('#'): k,v=l.strip().split('=',1); E[k]=v.strip().strip('"').strip("'")
    except Exception: pass
    return E
import MetaTrader5 as mt5
E=env(); MAXLOT=float(E.get('MT5_MAX_LOTS','2'))
def connect():
    if not E.get('MT5_LOGIN'): log("no MT5_LOGIN on the box: dormant"); return False
    ok=mt5.initialize(login=int(E['MT5_LOGIN']),password=E.get('MT5_PASSWORD',''),server=E.get('MT5_SERVER',''))
    if not ok: log(f"initialize failed {mt5.last_error()}"); return False
    a=mt5.account_info()
    if a is None: log("no account info"); return False
    if a.trade_mode!=mt5.ACCOUNT_TRADE_MODE_DEMO and E.get('MT5_ALLOW_LIVE')!='1':
        log("REFUSING: account is not DEMO and MT5_ALLOW_LIVE is not set"); mt5.shutdown(); return False
    log(f"connected login {a.login} server {a.server} demo={a.trade_mode==mt5.ACCOUNT_TRADE_MODE_DEMO} equity {a.equity} {a.currency}"); return True
def heartbeat():
    a=mt5.account_info(); pos=mt5.positions_get() or []
    json.dump(dict(t=dt.datetime.utcnow().isoformat(),login=a.login if a else None,equity=a.equity if a else None,balance=a.balance if a else None,
                   currency=a.currency if a else None,demo=(a.trade_mode==mt5.ACCOUNT_TRADE_MODE_DEMO) if a else None,killed=os.path.exists(KILL),
                   positions=[dict(ticket=p.ticket,symbol=p.symbol,type='buy' if p.type==0 else 'sell',volume=p.volume,price=p.price_open,sl=p.sl,tp=p.tp,profit=p.profit,comment=p.comment) for p in pos]),
              open(HB+'.tmp','w')); os.replace(HB+'.tmp',HB)
def close_position(p,comment='close'):
    tick=mt5.symbol_info_tick(p.symbol); typ=mt5.ORDER_TYPE_SELL if p.type==0 else mt5.ORDER_TYPE_BUY
    price=tick.bid if p.type==0 else tick.ask
    return mt5.order_send(dict(action=mt5.TRADE_ACTION_DEAL,symbol=p.symbol,volume=p.volume,type=typ,position=p.ticket,price=price,deviation=50,magic=777,comment=comment[:25],type_time=mt5.ORDER_TIME_GTC,type_filling=fill_mode(p.symbol)))
def fill_mode(sym):
    i=mt5.symbol_info(sym); fm=i.filling_mode if i else 0
    return mt5.ORDER_FILLING_FOK if fm&1 else (mt5.ORDER_FILLING_IOC if fm&2 else mt5.ORDER_FILLING_RETURN)
def handle(o):
    act=o.get('action','open')
    if act=='symbols':
        pat=o.get('pattern','*'); s=mt5.symbols_get(pat) or []
        return dict(ok=True,symbols=[dict(name=x.name,desc=x.description,digits=x.digits,contract=x.trade_contract_size,vol_min=x.volume_min,vol_step=x.volume_step,tick_value=x.trade_tick_value,tick_size=x.trade_tick_size) for x in s[:200]])
    if act=='quote':
        mt5.symbol_select(o['symbol'],True); t=mt5.symbol_info_tick(o['symbol']); return dict(ok=t is not None,bid=t.bid if t else None,ask=t.ask if t else None)
    if act in ('close_all','close_tag'):
        res=[]
        for p in (mt5.positions_get() or []):
            if act=='close_all' or (p.comment or '').startswith(o.get('tag','~')): r=close_position(p,o.get('tag','close')); res.append(dict(ticket=p.ticket,retcode=r.retcode if r else None))
        return dict(ok=True,closed=res)
    if act=='open':
        if os.path.exists(KILL): return dict(ok=False,error='KILL switch present')
        sym=o['symbol']; mt5.symbol_select(sym,True); info=mt5.symbol_info(sym); t=mt5.symbol_info_tick(sym)
        if info is None or t is None: return dict(ok=False,error=f'unknown symbol {sym}')
        vol=float(o['volume']); vol=min(vol,MAXLOT); step=info.volume_step; vol=max(info.volume_min,round(round(vol/step)*step,8))
        buy=o['side']=='buy'; price=t.ask if buy else t.bid
        req=dict(action=mt5.TRADE_ACTION_DEAL,symbol=sym,volume=vol,type=mt5.ORDER_TYPE_BUY if buy else mt5.ORDER_TYPE_SELL,price=price,deviation=int(o.get('deviation',50)),
                 magic=777,comment=o.get('tag','pe')[:25],type_time=mt5.ORDER_TIME_GTC,type_filling=fill_mode(sym))
        if o.get('sl'): req['sl']=round(float(o['sl']),info.digits)
        if o.get('tp'): req['tp']=round(float(o['tp']),info.digits)
        r=mt5.order_send(req)
        return dict(ok=bool(r and r.retcode==mt5.TRADE_RETCODE_DONE),retcode=r.retcode if r else None,comment=r.comment if r else str(mt5.last_error()),
                    order=r.order if r else None,deal=r.deal if r else None,price=r.price if r else None,volume=vol)
    return dict(ok=False,error=f'unknown action {act}')
def main():
    while not connect(): time.sleep(60); E.update(env())
    last_kill=False
    while True:
        try:
            if not mt5.terminal_info(): log("terminal lost, reconnecting"); mt5.shutdown(); time.sleep(10); connect(); continue
            k=os.path.exists(KILL)
            if k and not last_kill: log("KILL: closing everything"); handle(dict(action='close_all',tag='KILL'))
            last_kill=k
            for f in sorted(glob.glob(f'{INBOX}/*.json')):
                oid=os.path.basename(f)[:-5]
                try: o=json.load(open(f)); res=handle(o)
                except Exception as e: res=dict(ok=False,error=repr(e)[:200])
                res['id']=oid; res['t']=dt.datetime.utcnow().isoformat()
                json.dump(res,open(f'{OUTBOX}/{oid}.json.tmp','w')); os.replace(f'{OUTBOX}/{oid}.json.tmp',f'{OUTBOX}/{oid}.json'); os.replace(f,f'{DONE}/{oid}.json'); log(f"{oid} {o.get('action','open')} -> {res.get('ok')} {res.get('retcode','')}")
            heartbeat()
        except Exception: log(traceback.format_exc()[-500:])
        time.sleep(2)
if __name__=='__main__': main()
PY
cat > mt5_client.py <<'PY'
# Linux side of the MT5 bridge: write an order file, wait for the answer. Used by the strategy runners.
import os, json, time, uuid
BASE='/root/pe-fin/mt5'
def call(o,timeout=30):
    os.makedirs(f'{BASE}/inbox',exist_ok=True); oid=dt_id(); p=f'{BASE}/inbox/{oid}.json'
    json.dump(o,open(p+'.tmp','w')); os.replace(p+'.tmp',p)
    out=f'{BASE}/outbox/{oid}.json'; t0=time.time()
    while time.time()-t0<timeout:
        if os.path.exists(out): return json.load(open(out))
        time.sleep(0.5)
    return dict(ok=False,error='bridge timeout',id=oid)
def dt_id():
    import datetime as dt; return f"{dt.datetime.utcnow():%Y%m%d%H%M%S}_{uuid.uuid4().hex[:6]}"
def heartbeat():
    try: return json.load(open(f'{BASE}/heartbeat.json'))
    except Exception: return None
def alive(max_age_s=60):
    import datetime as dt; h=heartbeat()
    return bool(h) and (dt.datetime.utcnow()-dt.datetime.fromisoformat(h['t'])).total_seconds()<max_age_s
PY
python3 -m py_compile mt5_client.py || exit 1
cp mt5_client.py /root/pe-fin/team/mt5_client.py
cat > run_bridge.sh <<'SH'
#!/bin/bash
# start the bridge only when a login exists and the terminal is up; never twice
grep -q '^MT5_LOGIN=' /root/pe-logger/.env 2>/dev/null || exit 0
export WINEPREFIX=/root/.mt5wine WINEARCH=win64 WINEDEBUG=-all DISPLAY=:99
/root/pe-fin/mt5/run_terminal.sh
pgrep -f mt5_bridge.py >/dev/null && exit 0
sleep 20; (wine "$WINEPREFIX/drive_c/Program Files/Python310/python.exe" Z:/root/pe-fin/mt5/mt5_bridge.py >/dev/null 2>&1 &)
SH
chmod +x run_bridge.sh
( crontab -l 2>/dev/null | grep -v run_bridge.sh; echo "*/5 * * * * /root/pe-fin/mt5/run_bridge.sh" ) | crontab -
grep -q "mt5_setup\|bridge.log" /root/pe-fin/team/diag.sh || sed -i 's#^} > $D 2>&1#  echo; echo "\#\# mt5 bridge log"; tail -6 /root/pe-fin/mt5/bridge.log 2>/dev/null; echo; echo "\#\# mt5 heartbeat"; cat /root/pe-fin/mt5/heartbeat.json 2>/dev/null | head -c 600\n} > $D 2>\&1#' /root/pe-fin/team/diag.sh
bash -n /root/pe-fin/team/diag.sh && echo "diag: mt5 lines added"
echo "bridge deployed (dormant until MT5_LOGIN is on the box)"
