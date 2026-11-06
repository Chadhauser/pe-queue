#!/bin/bash
# 510: three faults found in the 6 Nov scoreboard, fixed here: (1) alpaca_daily.py crashed (it cut alpaca_pull.py before fetch_month was
# defined) so the Alpaca feeds show BROKEN since 30 Oct — rewritten standalone and run now; (2) H6 stuck 'running' because 509 restarted
# the daemon mid-build — daemon now resets 'running' to 'proposed' on start, H6 timeout 3h; (3) H1-5 rejected by the look-ahead critic
# for a calendar shift(-1) in the month-end test — rewritten without it and re-queued (507 already ran them: all NOT YET).
cd /root/pe-fin/team || exit 1
cat > alpaca_daily.py <<'PY'
import os, sys, time, datetime, requests, pandas as pd
sys.path.insert(0,'/root/pe-queue/runner'); import creds
E=creds.all_vars(); H={'APCA-API-KEY-ID':E.get('ALPACA_KEY'),'APCA-API-SECRET-KEY':E.get('ALPACA_SECRET')}; BASE='/root/pe-data/alpaca'
def fetch_month(sym,m0):
    m1=(m0.replace(day=28)+datetime.timedelta(days=4)).replace(day=1); frames=[]; tok=None
    while True:
        p={'symbols':sym,'timeframe':'1Min','start':f"{m0}T00:00:00Z",'end':f"{m1}T00:00:00Z",'limit':10000,'feed':'iex','adjustment':'all','sort':'asc'}
        if tok: p['page_token']=tok
        r=None
        for a in range(6):
            r=requests.get('https://data.alpaca.markets/v2/stocks/bars',params=p,headers=H,timeout=60)
            if r.status_code==429: time.sleep(5+5*a); continue
            if r.status_code>=500: time.sleep(3); continue
            break
        if r is None or r.status_code!=200: print(sym,"HTTP",getattr(r,'status_code',None),getattr(r,'text','')[:100]); return None
        j=r.json(); bars=(j.get('bars') or {}).get(sym) or []
        if bars: frames.append(pd.DataFrame(bars))
        tok=j.get('next_page_token')
        if not tok: break
        time.sleep(0.3)
    if not frames: return pd.DataFrame()
    b=pd.concat(frames); b['ts']=pd.to_datetime(b['t'],utc=True); b=b.set_index('ts').sort_index()
    b=b.rename(columns={'o':'open','h':'high','l':'low','c':'close','v':'volume','n':'ticks'})[['open','high','low','close','volume','ticks']]
    return b[~b.index.duplicated()]
m0=datetime.date.today().replace(day=1); n=0; last=None
for sym in sorted(os.listdir(BASE)):
    if not os.path.isdir(f"{BASE}/{sym}"): continue
    b=fetch_month(sym,m0)
    if b is None or b.empty: continue
    b.to_parquet(f"{BASE}/{sym}/1m_{m0:%Y-%m}.parquet"); n+=1; last=b.index.max()
print(f"refreshed current-month files: {n} | last bar {last}")
PY
python3 - <<'PY'
import re
s=open('fin_team.py').read()
if "reset_running" not in s:
    s=s.replace("if __name__=='__main__':","""def reset_running():
    reg=jload(REG,{'hypotheses':[]}); n=0
    for h in reg['hypotheses']:
        if h.get('status')=='running': h['status']='proposed'; n+=1
    json.dump(reg,open(REG,'w'),indent=1); log(f"start: reset {n} running -> proposed")
if __name__=='__main__':
    reset_running()""")
    open('fin_team.py','w').write(s)
m=open('mechanisms.py').read()
m=m.replace("me=qd.dt.month!=qd.shift(-1).dt.month","me=qd==qd.groupby([qd.dt.year,qd.dt.month]).transform('max')")
open('mechanisms.py','w').write(m)
import json; reg=json.load(open('hypotheses.json'))
for h in reg['hypotheses']:
    if h['id'].startswith('H1-5'): h['status']='proposed'; h.pop('note',None)
    if h['id'].startswith('H6'): h['timeout']=10800; h['status']='proposed'
json.dump(reg,open('hypotheses.json','w'),indent=1); print("queue:",[(h['id'],h['status']) for h in reg['hypotheses']])
PY
python3 -m py_compile fin_team.py mechanisms.py alpaca_daily.py || exit 1
grep -c "shift(-" mechanisms.py; echo "(must be 0)"
echo "== repairing Alpaca feeds now"; timeout 1500 python3 alpaca_daily.py 2>&1 | tail -2
pkill -f 'fin_team.py'; sleep 1; nohup /root/pe-fin/team/run_team.sh & disown; sleep 100
pgrep -f fin_team.py >/dev/null && echo "daemon running" || { echo "DAEMON NOT RUNNING"; exit 1; }
cat scoreboard.md; echo; tail -6 team.log
