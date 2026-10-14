#!/bin/bash
# 066: BETFAIR BASIC HISTORY FOR EVERY SPORT — the Basic plan is free, so "owned" is not the constraint; this lists and loads
# tennis, cricket, horse racing (GB/IE WIN), greyhounds (GB/IE WIN), basketball, and the 2nd+ football markets we lack (CORRECT_SCORE),
# Sep 2024 -> Sep 2026, month by month, resumable, into bf_hist_other. Big: runs for hours; exit 75 keeps it cycling until complete.
# Uses the Historic Data API with the SSO token job 010 keeps in .env (re-logs in if stale). Lists the files for each (sport, month);
# if the list comes back empty/403 the month is not owned -> says so (Peter decides purchases) and moves on. Downloads to
# /root/bfdata/<sport>/, parses the bz2 stream and stores 1 row per runner per minute: table bf_hist_other
# (sport, market_id, event_id, event_name, market_type, market_time, country, sel, ts, ltp, inplay). Resumable.
python3 - <<'PY'
import os, re, sys, bz2, json, time, datetime, requests, psycopg2, psycopg2.extras
sys.path.insert(0,'/root/pe-queue/runner'); import creds
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
APP,U,P=creds.betfair(); E=creds.all_vars()
def ok(tok): return requests.get("https://historicdata.betfair.com/api/GetMyData",headers={"ssoid":tok},timeout=20).status_code==200
tok=E.get('BF_SSOID')
if not (tok and ok(tok)):
    r=requests.post("https://identitysso.betfair.com/api/login",data={"username":U,"password":P},headers={"X-Application":APP,"Accept":"application/json"},timeout=20).json()
    if r.get('status')!='SUCCESS': print("WAITING: SSO login failed",r.get('error')); sys.exit(75)
    tok=r['token']
    if not ok(tok): print("WAITING: token not accepted by Historic Data API"); sys.exit(75)
H={"ssoid":tok,"content-type":"application/json"}
print("my data (owned purchases):"); 
try:
    md=requests.get("https://historicdata.betfair.com/api/GetMyData",headers=H,timeout=30).json()
    for d in md: print("  ",d.get('sport'),d.get('plan'),d.get('forDate'),d.get('purchaseItemId'))
except Exception as e: print("  GetMyData parse:",repr(e)[:100])
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("""CREATE TABLE IF NOT EXISTS bf_hist_other (sport TEXT, market_id TEXT, event_id TEXT, event_name TEXT, market_type TEXT, market_time TIMESTAMPTZ, country TEXT,
  sel TEXT, ts TIMESTAMPTZ, ltp NUMERIC, inplay BOOLEAN); CREATE INDEX IF NOT EXISTS bfo_mkt ON bf_hist_other (sport, market_id);
  CREATE TABLE IF NOT EXISTS bf_hist_other_files (path TEXT PRIMARY KEY, loaded_at TIMESTAMPTZ)""")
cur.execute("SELECT path FROM bf_hist_other_files"); done={r[0] for r in cur.fetchall()}
WANT=[]
for y,m in [(yy,mm) for yy in (2024,2025,2026) for mm in range(1,13) if (yy,mm)>=(2024,9) and (yy,mm)<=(2026,9)]:
    WANT+=[("Tennis",y,m,["MATCH_ODDS"],None),("Cricket",y,m,["MATCH_ODDS"],None),("Horse Racing",y,m,["WIN"],["GB","IE"]),("Greyhound Racing",y,m,["WIN"],["GB","IE"]),("Basketball",y,m,["MATCH_ODDS"],None),("Soccer",y,m,["CORRECT_SCORE"],None)]
import time as _t; T0=_t.time(); BUDGET=50*60   # 50 minutes per run, then exit 75 and continue next cycle
import calendar
for sport,y,m,mts,countries in WANT:
    if _t.time()-T0>BUDGET: print("time budget used; continuing next cycle"); sys.exit(75)
    cur.execute("SELECT 1 FROM bf_hist_other_files WHERE path=%s",(f"DONE::{sport}::{y}-{m:02d}",))
    if cur.fetchone(): continue
    body={"sport":sport,"plan":"Basic Plan","fromDay":1,"fromMonth":m,"fromYear":y,"toDay":calendar.monthrange(y,m)[1],"toMonth":m,"toYear":y,"marketTypesCollection":mts,"countriesCollection":countries or [],"fileTypeCollection":["M"]}
    r=requests.post("https://historicdata.betfair.com/api/DownloadListOfFiles",headers=H,json=body,timeout=120)
    if r.status_code!=200: print(f"{sport} {y}-{m:02d}: LIST HTTP {r.status_code} -> not owned or API refused ({r.text[:120]})"); continue
    files=r.json(); print(f"{sport} {y}-{m:02d}: {len(files)} files listed",flush=True)
    if not files: print("   -> empty list (nothing for that month or not in plan)"); cur.execute("INSERT INTO bf_hist_other_files VALUES (%s,NOW()) ON CONFLICT DO NOTHING",(f"DONE::{sport}::{y}-{m:02d}",)); continue
    base=f"/root/bfdata/{sport.replace(' ','_').lower()}"; os.makedirs(base,exist_ok=True); n=0; rows=[]
    for fp in files:
        if fp in done: continue
        local=os.path.join(base,fp.strip('/').replace('/','__'))
        if not os.path.exists(local):
            for attempt in range(3):
                try:
                    d=requests.get("https://historicdata.betfair.com/api/DownloadFile",params={"filePath":fp},headers={"ssoid":tok},timeout=120)
                    if d.status_code==200: open(local,'wb').write(d.content); break
                    if d.status_code==429: time.sleep(20)
                except Exception: time.sleep(5)
            else: print("   download failed",fp); continue
        try: lines=bz2.open(local,'rt').read().split('\n')
        except Exception: continue
        md_=None; runners={}; last_min={}; inplay=False
        for ln in lines:
            if not ln: continue
            try: o=json.loads(ln)
            except: continue
            pt=o.get('pt')
            for mc in o.get('mc',[]):
                if 'marketDefinition' in mc:
                    md_=mc['marketDefinition']; runners.update({x['id']:x['name'] for x in md_.get('runners',[])}); inplay=bool(md_.get('inPlay'))
                if not md_: continue
                for rc in mc.get('rc',[]):
                    if 'ltp' in rc and rc['id'] in runners:
                        k=(rc['id'],pt//60000)
                        last_min[k]=(pt,rc['ltp'],inplay)
        if not md_: continue
        mid=mc.get('id') if 'mc' in o and o['mc'] else None
        mid=md_.get('marketId') or os.path.basename(fp).split('.')[0]
        for (sid,_),(pt,p,ip) in last_min.items():
            rows.append((sport,mid,str(md_.get('eventId')),md_.get('eventName'),md_.get('marketType'),md_.get('marketTime'),md_.get('countryCode'),runners[sid],datetime.datetime.utcfromtimestamp(pt/1000).replace(tzinfo=datetime.timezone.utc),p,ip))
        cur.execute("INSERT INTO bf_hist_other_files VALUES (%s,NOW()) ON CONFLICT DO NOTHING",(fp,)); n+=1
        if len(rows)>=20000: psycopg2.extras.execute_values(cur,"INSERT INTO bf_hist_other VALUES %s",rows,page_size=5000); rows=[]
        if n%200==0: print("   loaded",n,"files",flush=True)
    if rows: psycopg2.extras.execute_values(cur,"INSERT INTO bf_hist_other VALUES %s",rows,page_size=5000)
    print(f"   {sport} {y}-{m:02d}: {n} files loaded this run",flush=True)
    cur.execute("INSERT INTO bf_hist_other_files VALUES (%s,NOW()) ON CONFLICT DO NOTHING",(f"DONE::{sport}::{y}-{m:02d}",))
cur.execute("SELECT sport, market_type, count(DISTINCT market_id), count(*), min(market_time)::date, max(market_time)::date FROM bf_hist_other GROUP BY 1,2"); print("bf_hist_other now:",cur.fetchall())
PY
