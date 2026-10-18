#!/bin/bash
# 088 (087 re-issued: bf_hist_price has no market_time column - soccer skip is now by fixed date range):
# 087: BASIC HISTORY LOADER v3 — DRIVEN OFF GetMyData. Peter added the £0 Basic months on the Purchase page (15 Oct 13:44); this
# reads the owned list itself, so nothing is hard-coded and anything he adds later is picked up automatically. Replaces 064/066.
# Rules: 8-minute budget per run then exit 75 (re-run every 2 min until every owned month is loaded, never blocks the queue);
# local bz2 deleted after parsing (server disk); stops with WAITING if DB > 38 GB (volume is 50 GB from 17 Oct) so disk can never fill again.
# Order: sports we hold nothing for first (tennis, greyhounds, basketball), then cricket, racing, golf, then soccer extras.
# Storage: bf_hist_other, 1 row per runner per minute (LTP, inplay), progress in bf_hist_other_files + bf_hist_months.
python3 - <<'PY'
import os, sys, bz2, json, time, calendar, datetime, shutil, requests, psycopg2, psycopg2.extras
sys.path.insert(0,'/root/pe-queue/runner'); import creds
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
T0=time.time(); BUDGET=2*60
APP,U,P=creds.betfair(); E=creds.all_vars()
def ok(tok): return requests.get("https://historicdata.betfair.com/api/GetMyData",headers={"ssoid":tok},timeout=20).status_code==200
tok=E.get('BF_SSOID')
if not (tok and ok(tok)):
    r=requests.post("https://identitysso.betfair.com/api/login",data={"username":U,"password":P},headers={"X-Application":APP,"Accept":"application/json"},timeout=20).json()
    if r.get('status')!='SUCCESS': print("WAITING: SSO login failed",r.get('error')); sys.exit(75)
    tok=r['token']
    if not ok(tok): print("WAITING: token not accepted by Historic Data API"); sys.exit(75)
H={"ssoid":tok,"content-type":"application/json"}
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("SELECT pg_database_size(current_database())/1e9"); gb=cur.fetchone()[0]; print(f"DB size {gb:.1f} GB")
if gb>38: print("WAITING: DB over 38 GB — not loading more until pruned"); sys.exit(75)
if shutil.disk_usage('/root').free<2e9: print("WAITING: server disk under 2 GB free"); sys.exit(75)
cur.execute("""CREATE TABLE IF NOT EXISTS bf_hist_other (sport TEXT, market_id TEXT, event_id TEXT, event_name TEXT, market_type TEXT, market_time TIMESTAMPTZ, country TEXT,
  sel TEXT, ts TIMESTAMPTZ, ltp NUMERIC, inplay BOOLEAN); CREATE INDEX IF NOT EXISTS bfo_mkt ON bf_hist_other (sport, market_id);
  CREATE TABLE IF NOT EXISTS bf_hist_other_files (path TEXT PRIMARY KEY, loaded_at TIMESTAMPTZ);
  CREATE TABLE IF NOT EXISTS bf_hist_months (sport TEXT, y INT, m INT, status TEXT, files INT, loaded INT, updated TIMESTAMPTZ, PRIMARY KEY (sport,y,m))""")
md=requests.get("https://historicdata.betfair.com/api/GetMyData",headers=H,timeout=30).json()
owned=set()
for d in md:
    try:
        fd=str(d.get('forDate'))[:7]; y,m=int(fd[:4]),int(fd[5:7]); owned.add((d.get('sport'),y,m))
    except Exception: pass
print("owned sport-months:",len(owned))
# what each sport is for, in our tables
SPEC={'Tennis':(['MATCH_ODDS'],[]),'Greyhound Racing':(['WIN'],['GB','IE']),'Basketball':(['MATCH_ODDS'],[]),'Cricket':(['MATCH_ODDS'],[]),
      'Horse Racing':(['WIN'],['GB','IE']),'Golf':(['OUTRIGHT_WINNER','TOURNAMENT_WINNER'],[]),'Soccer':(['MATCH_ODDS','OVER_UNDER_25'],[])}
PRIO=['Tennis','Greyhound Racing','Basketball','Cricket','Horse Racing','Golf','Soccer']
cur.execute("SELECT sport,y,m,status FROM bf_hist_months"); st={(a,b,c):d for a,b,c,d in cur.fetchall()}
# soccer Aug 2024 - Jun 2026 already in bf_hist_price (2 seasons, 7 markets) - skip those months here
for y in (2024,2025,2026):
    for m in range(1,13):
        if (y,m)>=(2024,8) and (y,m)<=(2026,6): st.setdefault(('Soccer',y,m),'DONE_PRICE')
todo=[(s,y,m) for s in PRIO for (sp,y,m) in sorted(owned,key=lambda x:(x[1],x[2]),reverse=True) if sp==s and st.get((s,y,m)) not in ('DONE','DONE_PRICE','EMPTY')]
print("months still to load:",len(todo),"| first:",todo[:5])
cur.execute("SELECT path FROM bf_hist_other_files"); done={r[0] for r in cur.fetchall()}
def parse(local):
    md_=None; runners={}; last_min={}; inplay=False
    with bz2.open(local,'rt') as f:
        for ln in f:
            if not ln.strip(): continue
            try: o=json.loads(ln)
            except Exception: continue
            pt=o.get('pt')
            for mc in o.get('mc',[]):
                if 'marketDefinition' in mc:
                    md_=mc['marketDefinition']; runners.update({x['id']:x['name'] for x in md_.get('runners',[])}); inplay=bool(md_.get('inPlay'))
                if not md_: continue
                for rc in mc.get('rc',[]):
                    if 'ltp' in rc and rc['id'] in runners: last_min[(rc['id'],pt//60000)]=(pt,rc['ltp'],inplay)
    return md_,runners,last_min
for sport,y,m in todo:
    if time.time()-T0>BUDGET: break
    mts,ctry=SPEC.get(sport,(['MATCH_ODDS'],[]))
    body={"sport":sport,"plan":"Basic Plan","fromDay":1,"fromMonth":m,"fromYear":y,"toDay":calendar.monthrange(y,m)[1],"toMonth":m,"toYear":y,"marketTypesCollection":mts,"countriesCollection":ctry,"fileTypeCollection":["M"]}
    r=requests.post("https://historicdata.betfair.com/api/DownloadListOfFiles",headers=H,json=body,timeout=180)
    if r.status_code!=200: print(f"{sport} {y}-{m:02d}: LIST HTTP {r.status_code} {r.text[:100]}"); cur.execute("INSERT INTO bf_hist_months VALUES (%s,%s,%s,'LISTFAIL',0,0,NOW()) ON CONFLICT (sport,y,m) DO UPDATE SET status='LISTFAIL',updated=NOW()",(sport,y,m)); continue
    files=r.json()
    if not files: print(f"{sport} {y}-{m:02d}: empty list"); cur.execute("INSERT INTO bf_hist_months VALUES (%s,%s,%s,'EMPTY',0,0,NOW()) ON CONFLICT (sport,y,m) DO UPDATE SET status='EMPTY',updated=NOW()",(sport,y,m)); continue
    base=f"/root/bfdata/{sport.replace(' ','_').lower()}"; os.makedirs(base,exist_ok=True); n=0; rows=[]; pending=[f for f in files if f not in done]
    print(f"{sport} {y}-{m:02d}: {len(files)} files, {len(pending)} to load",flush=True)
    for fp in pending:
        if time.time()-T0>BUDGET: break
        local=os.path.join(base,os.path.basename(fp))
        got=False
        for attempt in range(3):
            try:
                d=requests.get("https://historicdata.betfair.com/api/DownloadFile",params={"filePath":fp},headers={"ssoid":tok},timeout=120)
                if d.status_code==200: open(local,'wb').write(d.content); got=True; break
                if d.status_code==429: time.sleep(20)
            except Exception: time.sleep(5)
        if not got: continue
        try: md_,runners,last_min=parse(local)
        except Exception as e: md_=None
        try: os.remove(local)
        except Exception: pass
        if md_:
            mid=os.path.basename(fp).replace('.bz2','')
            for (sid,_),(pt,p,ip) in last_min.items():
                rows.append((sport,mid,str(md_.get('eventId')),md_.get('eventName'),md_.get('marketType'),md_.get('marketTime'),md_.get('countryCode'),runners[sid],datetime.datetime.utcfromtimestamp(pt/1000).replace(tzinfo=datetime.timezone.utc),p,ip))
        cur.execute("INSERT INTO bf_hist_other_files VALUES (%s,NOW()) ON CONFLICT DO NOTHING",(fp,)); done.add(fp); n+=1
        if len(rows)>=20000: psycopg2.extras.execute_values(cur,"INSERT INTO bf_hist_other VALUES %s",rows,page_size=5000); rows=[]
    if rows: psycopg2.extras.execute_values(cur,"INSERT INTO bf_hist_other VALUES %s",rows,page_size=5000)
    left=len([f for f in files if f not in done]); status='DONE' if left==0 else 'PARTIAL'
    cur.execute("INSERT INTO bf_hist_months VALUES (%s,%s,%s,%s,%s,%s,NOW()) ON CONFLICT (sport,y,m) DO UPDATE SET status=EXCLUDED.status,files=EXCLUDED.files,loaded=EXCLUDED.loaded,updated=NOW()",(sport,y,m,status,len(files),len(files)-left))
    print(f"   {sport} {y}-{m:02d}: +{n} files this run, {left} left -> {status}",flush=True)
cur.execute("SELECT sport, count(*) FILTER (WHERE status='DONE'), count(*) FILTER (WHERE status<>'DONE'), sum(loaded) FROM bf_hist_months GROUP BY 1 ORDER BY 1")
print("progress by sport (done months, other months, files loaded):",cur.fetchall())
cur.execute("SELECT sport, count(DISTINCT market_id), min(market_time)::date, max(market_time)::date FROM bf_hist_other GROUP BY 1 ORDER BY 1"); print("bf_hist_other:",cur.fetchall())
cur.execute("SELECT sport,y,m,status FROM bf_hist_months")
for a,b,c,d in cur.fetchall(): st[(a,b,c)]=d
remaining=[t for t in owned if st.get(t) not in ('DONE','DONE_PRICE','EMPTY')]
if remaining: print(f"WAITING: {len(remaining)} owned months still to load — re-running"); sys.exit(75)
print("ALL OWNED MONTHS LOADED")
PY
