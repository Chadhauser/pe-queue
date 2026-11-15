#!/bin/bash
# 525: K2 (small-cap overnight gap fade, no earnings) came out WORKS in the backtest at +168 bps/trade, t 23 — far too good to
# trust on daily bars from thin names (stale/odd-lot opening prints, current-list survivorship). The only honest next check is
# forward paper at real quotes: from Monday, at 09:31 ET scan the small universe on Alpaca snapshots, take |gap| >= 5% names with no
# earnings within a day, FADE with $500 notional each (max 10), flat 15:55 ET, log fills. Alpaca PAPER endpoint only.
# Also: the earnings-date pull now keeps UPCOMING dates (needed to exclude tomorrow's reporters), refreshed weekly.
cd /root/pe-fin/team && sed -i "s/if i.date()<=dt.date.today()})/})/" crumbs_pull.py && python3 -m py_compile crumbs_pull.py || exit 1
mkdir -p /root/pe-fin/bot && cd /root/pe-fin/bot || exit 1
cat > k2_gapfade_bot.py <<'PY'
import os, sys, json, time, datetime as dt, requests, traceback, zoneinfo, pandas as pd
sys.path.insert(0,'/root/pe-queue/runner'); import creds
E=creds.all_vars(); K,S=E.get('ALPACA_KEY'),E.get('ALPACA_SECRET')
T='https://paper-api.alpaca.markets/v2'   # PAPER ONLY
H={'APCA-API-KEY-ID':K,'APCA-API-SECRET-KEY':S}; LOG='/root/pe-fin/bot/k2.log'; TR='/root/pe-fin/bot/k2_trades.json'
NY=zoneinfo.ZoneInfo('America/New_York'); NOTIONAL=500.0; MAXN=10; GAP=0.05
def log(m):
    line=f"{dt.datetime.now(NY):%Y-%m-%d %H:%M:%S} {m}"; print(line,flush=True); open(LOG,'a').write(line+"\n")
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
def run_day():
    today=dt.datetime.now(NY).date(); trades=jl(TR,[])
    if any(t.get('date')==str(today) for t in trades): log("already ran today"); return
    sc,clk=api('GET','/clock')
    if sc==200 and not clk.get('is_open'): log("market closed"); return
    uni=list(pd.read_csv('/root/pe-data/crumbs/universe_small.csv',index_col=0).index); ed=jl('/root/pe-data/crumbs/earnings_dates.json',{})
    t0=dt.datetime.combine(today,dt.time(9,31,0),tzinfo=NY)
    while dt.datetime.now(NY)<t0: time.sleep(1)
    snap=snapshots(uni); cands=[]
    for s,v in snap.items():
        try:
            prev=v['prevDailyBar']['c']; lt=v['latestTrade']; px=lt['p']; ts=pd.Timestamp(lt['t'])
            if ts<pd.Timestamp(dt.datetime.combine(today,dt.time(9,30),tzinfo=NY)): continue   # no print yet today: untradeable, skip
            gap=px/prev-1
            if abs(gap)<GAP or px<3: continue
            near=any(abs((pd.Timestamp(d).date()-today).days)<=1 for d in ed.get(s,[]))
            if near: continue
            cands.append(dict(sym=s,px=px,prev=prev,gap=gap))
        except Exception: continue
    cands=sorted(cands,key=lambda c:-abs(c['gap']))[:MAXN]; log(f"scanned {len(snap)} | candidates {len(cands)}: {[(c['sym'],round(c['gap'],3)) for c in cands]}")
    day=dict(date=str(today),legs=[])
    for c in cands:
        qty=max(1,int(NOTIONAL//c['px'])); side='sell' if c['gap']>0 else 'buy'
        sc,res=api('POST','/orders',json={'symbol':c['sym'],'qty':str(qty),'side':side,'type':'market','time_in_force':'day'})
        day['legs'].append(dict(sym=c['sym'],side=side,qty=qty,ref_px=c['px'],gap=round(c['gap'],4),order_id=res.get('id') if isinstance(res,dict) else None,status=sc)); log(f"{side} {qty} {c['sym']} @~{c['px']} gap {c['gap']:+.1%} -> {sc}")
    trades.append(day); json.dump(trades,open(TR,'w'),indent=1)
    if not cands: return
    t_flat=dt.datetime.combine(today,dt.time(15,55),tzinfo=NY)
    while dt.datetime.now(NY)<t_flat: time.sleep(30)
    api('DELETE','/orders')
    for leg in day['legs']:
        sc,pos=api('GET',f"/positions/{leg['sym']}")
        if sc==200 and float(pos.get('qty',0))!=0: api('DELETE',f"/positions/{leg['sym']}")
    time.sleep(25)
    sc,orders=api('GET','/orders',params={'status':'closed','after':dt.datetime.combine(today,dt.time(9,0),tzinfo=NY).isoformat(),'limit':200})
    fills={}
    if sc==200:
        for o_ in orders:
            if o_.get('filled_qty') and float(o_['filled_qty'])>0:
                f=fills.setdefault(o_['symbol'],{'buy':0.0,'sell':0.0}); f[o_['side']]+=float(o_['filled_qty'])*float(o_['filled_avg_price'] or 0)
    tot=0.0
    for leg in day['legs']:
        f=fills.get(leg['sym']); leg['pnl_usd']=round(f['sell']-f['buy'],2) if f else None; tot+=leg['pnl_usd'] or 0
    day['pnl_usd']=round(tot,2); json.dump(trades,open(TR,'w'),indent=1); log(f"DAY DONE {len(day['legs'])} legs pnl ${tot:+.2f}")
if __name__=='__main__':
    if '--check' in sys.argv:
        sc,acc=api('GET','/account'); print("CHECK",sc,acc.get('account_number') if isinstance(acc,dict) else acc); sys.exit(0 if sc==200 else 1)
    try: run_day()
    except Exception: log(traceback.format_exc()[-800:])
PY
python3 -m py_compile k2_gapfade_bot.py || exit 1
( crontab -l 2>/dev/null | grep -v k2_gapfade_bot.py; echo "20 13 * * 1-5 cd /root/pe-fin/bot && /usr/bin/python3 k2_gapfade_bot.py >> k2_cron.log 2>&1" ) | crontab -
python3 - <<'PY'
s=open('/root/pe-fin/team/fin_team.py').read()
if 'k2_trades' not in s:
    s=s.replace("""    L+=["","## Queue"]""","""    k2=jload('/root/pe-fin/bot/k2_trades.json',[])
    if k2:
        done=[d for d in k2 if d.get('pnl_usd') is not None]; L+=["",f"## Bot 2 — Alpaca PAPER, K2 small-cap gap fade, $500/name — {len(done)} days, ${sum(d['pnl_usd'] for d in done):+.2f}","","| date | names | pnl $ | legs |","|---|---|---|---|"]
        for d in k2[-10:]: L.append(f"| {d['date']} | {len(d['legs'])} | {d.get('pnl_usd','')} | {', '.join(f\"{l['sym']} {l['side']} {l.get('pnl_usd','')}\" for l in d['legs'])} |")
    L+=["","## Queue"]""")
    open('/root/pe-fin/team/fin_team.py','w').write(s); print('scoreboard: K2 bot section added')
PY
python3 -m py_compile /root/pe-fin/team/fin_team.py || exit 1
cd /root/pe-fin/team && (python3 crumbs_pull.py > /dev/null 2>&1 &) ; echo "earnings refresh (incl. upcoming) started in background"
cd /root/pe-fin/bot && python3 k2_gapfade_bot.py --check
