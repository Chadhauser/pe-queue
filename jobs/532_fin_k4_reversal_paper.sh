#!/bin/bash
# 532: K4 (small-cap 5-day crash reversal: backtest WORKS, t 3.8 by date, UNVERIFIED on fills) gets its own forward-paper bot on
# Alpaca PAPER, same as K2: 15:50 ET buy names down >=15% over 5 trading days (no earnings within a day), $500 each, max 10/day,
# sell on the 5th trading day; settle job at 21:30 UTC writes P&L per name. Scoreboard gets a "Bot 3" section.
mkdir -p /root/pe-fin/bot && cd /root/pe-fin/bot || exit 1
cat > k4_reversal_bot.py <<'PY'
# K4 FORWARD PAPER — small-cap 5-day crash reversal (backtest WORKS on daily data, UNVERIFIED on fills). Alpaca PAPER only.
# 15:50 ET each trading day: price now vs the close 5 trading days ago (Yahoo daily) for the thin universe; names down >=15% and
# not reporting earnings within a day are bought, $500 each, max 10 new per day; every position is sold at 15:50 ET on its 5th
# trading day. Records fills and P&L per name to k4_trades.json -> scoreboard. Never touches the live endpoint.
import os, sys, json, time, datetime as dt, requests, traceback, zoneinfo, pandas as pd
sys.path.insert(0,'/root/pe-queue/runner'); import creds
E=creds.all_vars(); T='https://paper-api.alpaca.markets/v2'
H={'APCA-API-KEY-ID':E.get('ALPACA_KEY',''),'APCA-API-SECRET-KEY':E.get('ALPACA_SECRET','')}
NY=zoneinfo.ZoneInfo('America/New_York'); LOG='/root/pe-fin/bot/k4.log'; TR='/root/pe-fin/bot/k4_trades.json'; NOTIONAL=500.0; MAXN=10; DROP=-0.15; HOLD=5
def log(m):
    l=f"{dt.datetime.now(NY):%Y-%m-%d %H:%M:%S} {m}"; print(l,flush=True); open(LOG,'a').write(l+"\n")
def jl(p,d):
    try: return json.load(open(p))
    except Exception: return d
def api(method,path,**kw):
    r=requests.request(method,f"{T}{path}",headers=H,timeout=30,**kw)
    try: j=r.json()
    except Exception: j=r.text
    if r.status_code>=300: log(f"{method} {path} -> {r.status_code} {str(j)[:160]}")
    return r.status_code,j
def snapshots(syms):
    out={}
    for i in range(0,len(syms),200):
        r=requests.get('https://data.alpaca.markets/v2/stocks/snapshots',params={'symbols':','.join(syms[i:i+200]),'feed':'iex'},headers=H,timeout=60)
        if r.status_code==200: out.update(r.json())
    return out
def trading_days_between(a,b):
    sc,cal=api('GET','/calendar',params={'start':str(a),'end':str(b)}); return len(cal) if sc==200 else 99
def run_day():
    today=dt.datetime.now(NY).date(); book=jl(TR,{'open':[],'closed':[]})
    sc,clk=api('GET','/clock')
    if sc==200 and not clk.get('is_open'): log("market closed"); return
    t=dt.datetime.combine(today,dt.time(15,50),tzinfo=NY)
    while dt.datetime.now(NY)<t: time.sleep(5)
    # exits first
    keep=[]
    for p in book['open']:
        if trading_days_between(dt.date.fromisoformat(p['date']),today)-1>=HOLD:
            sc,res=api('DELETE',f"/positions/{p['sym']}"); p['exit_date']=str(today); p['exit_order']=res.get('id') if isinstance(res,dict) else None; book['closed'].append(p); log(f"EXIT {p['sym']} after {HOLD} days -> {sc}")
        else: keep.append(p)
    book['open']=keep
    # entries
    uni=list(pd.read_csv('/root/pe-data/crumbs/universe_small.csv',index_col=0).index); ed=jl('/root/pe-data/crumbs/earnings_dates.json',{})
    import yfinance as yf
    d=yf.download(uni,period='15d',interval='1d',auto_adjust=False,progress=False,threads=True)['Close']
    d=d[d.index.date<today]
    if len(d)<5: log("not enough daily history"); json.dump(book,open(TR,'w'),indent=1); return
    ref=d.iloc[-5]   # close 5 trading days before today's close
    snap=snapshots(uni); cands=[]
    held={p['sym'] for p in book['open']}
    for s,v in snap.items():
        try:
            px=v['latestTrade']['p']; r5=px/ref[s]-1
            if r5>DROP or px<3 or s in held or pd.isna(r5): continue
            if any(abs((pd.Timestamp(x).date()-today).days)<=1 for x in ed.get(s,[])): continue
            cands.append(dict(sym=s,px=px,r5=r5))
        except Exception: continue
    cands=sorted(cands,key=lambda c:c['r5'])[:MAXN]; log(f"K4 candidates {len(cands)}: {[(c['sym'],round(c['r5'],3)) for c in cands]}")
    for c in cands:
        qty=max(1,int(NOTIONAL//c['px'])); sc,res=api('POST','/orders',json={'symbol':c['sym'],'qty':str(qty),'side':'buy','type':'market','time_in_force':'day'})
        if sc<300: book['open'].append(dict(sym=c['sym'],date=str(today),qty=qty,ref_px=c['px'],r5=round(c['r5'],4),order=res.get('id')))
    json.dump(book,open(TR,'w'),indent=1)
def settle():
    """fill prices for closed legs -> pnl; run after the close"""
    book=jl(TR,{'open':[],'closed':[]}); changed=False
    for p in book['closed']:
        if p.get('pnl_usd') is not None: continue
        sc1,o1=api('GET',f"/orders/{p['order']}") if p.get('order') else (0,{})
        sc2,o2=api('GET',f"/orders/{p['exit_order']}") if p.get('exit_order') else (0,{})
        if sc1==200 and sc2==200 and o1.get('filled_avg_price') and o2.get('filled_avg_price'):
            p['pnl_usd']=round((float(o2['filled_avg_price'])-float(o1['filled_avg_price']))*float(o1['filled_qty']),2); changed=True
    if changed: json.dump(book,open(TR,'w'),indent=1)
if __name__=='__main__':
    try:
        if '--settle' in sys.argv: settle()
        else: run_day()
    except Exception: log(traceback.format_exc()[-600:])
PY
python3 -m py_compile k4_reversal_bot.py || exit 1
( crontab -l 2>/dev/null | grep -v k4_reversal_bot.py; echo "35 20 * * 1-5 cd /root/pe-fin/bot && /usr/bin/python3 k4_reversal_bot.py >> k4_cron.log 2>&1"; echo "30 21 * * 1-5 cd /root/pe-fin/bot && /usr/bin/python3 k4_reversal_bot.py --settle >> k4_cron.log 2>&1" ) | crontab -
python3 - <<'PY'
s=open('/root/pe-fin/team/fin_team.py').read()
if 'k4_trades' not in s:
    s=s.replace("""    L+=["","## Queue"]""","""    k4=jload('/root/pe-fin/bot/k4_trades.json',{})
    if k4:
        cl=[p for p in k4.get('closed',[]) if p.get('pnl_usd') is not None]
        L+=["",f"## Bot 3 — Alpaca PAPER, K4 small-cap crash reversal, $500/name, 5-day hold — open {len(k4.get('open',[]))}, closed {len(cl)}, ${sum(p['pnl_usd'] for p in cl):+.2f}"]
        L+=[f"- open: {', '.join(p['sym']+' '+p['date'] for p in k4.get('open',[])[-12:])}"]
    L+=["","## Queue"]""")
    open('/root/pe-fin/team/fin_team.py','w').write(s); print('scoreboard: K4 bot section added')
PY
python3 -m py_compile /root/pe-fin/team/fin_team.py || exit 1
echo "K4 bot scheduled: 20:35 UTC entry/exit, 21:30 UTC settle"
