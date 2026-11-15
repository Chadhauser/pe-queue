# Results coverage by sport — 2026-11-15 15:56 UTC (job 586)

```
bf_hist_result columns: ['sport', 'market_id', 'event_id', 'market_type', 'sel', 'status', 'settled_time', 'market_status']
bf_hist_result by sport: [('Soccer', 8373127, 2081234)]
Traceback (most recent call last):
  File "<stdin>", line 5, in <module>
psycopg2.OperationalError: server closed the connection unexpectedly
	This probably means the server terminated abnormally
	before or while processing the request.

```
## /root/pe-hist
```
  
4096 2026-11-10_08:15 .
4096 2026-11-15_17:00 ..
0 2026-11-15_16:15 .adv.lock
4096 2026-11-10_07:40 __pycache__
108 2026-11-04_19:16 keepalive_hist.sh
209971 2026-11-15_16:56 loader.log
501 2026-11-04_19:16 loader.py
15351 2026-11-15_16:15 loader_adv.log
7499 2026-11-10_07:40 loader_adv.py
9642 2026-11-05_12:38 loader_core.py
7685 2026-11-05_07:53 loader_core.py.bak_353
8841 2026-11-05_12:38 loader_core.py.bak_406
8841 2026-11-05_12:12 loader_core.py.bak_520
9642 2026-11-05_12:38 loader_core.py.bak_521
```
### /root/pe-hist/loader.py (10 lines) — header + every line touching results, sport, files, status
```
import time as _t, traceback as _tb, sys as _s
while True:
    try:
        exec(compile(open(__file__.replace('loader.py','loader_core.py')).read(), 'loader_core.py', 'exec'), {'__name__':'__main__'})
        print("cycle complete; sleeping 1 h before re-reading the owned list", flush=True); _t.sleep(3600)
    except SystemExit as e:
        if e.code==75: print("waiting 10 min", flush=True); _t.sleep(600)
        else: _t.sleep(3600)
    except Exception:
        _tb.print_exc(); _t.sleep(300)
...
```
### /root/pe-hist/loader_adv.py (92 lines) — header + every line touching results, sport, files, status
```
import os, sys, bz2, json, time, calendar, datetime, shutil, requests, psycopg2, psycopg2.extras, fcntl
sys.path.insert(0,'/root/pe-queue/runner'); import creds
LOCK=open('/root/pe-hist/.adv.lock','w')
try: fcntl.flock(LOCK,fcntl.LOCK_EX|fcntl.LOCK_NB)
except OSError: print("another Advanced load is running"); sys.exit(0)
APP,U,P=creds.betfair()
r=requests.post("https://identitysso.betfair.com/api/login",data={"username":U,"password":P},headers={"X-Application":APP,"Accept":"application/json"},timeout=20).json()
tok=r.get('token'); H={"ssoid":tok,"Content-Type":"application/json"}
md=requests.get("https://historicdata.betfair.com/api/GetMyData",headers=H,timeout=30).json()
if md: print("GetMyData item keys:",sorted(md[0].keys()))
adv=set()
for d in md:
    plan=str(d.get('plan') or d.get('planName') or '')
    if 'advanced' in plan.lower() or 'pro' in plan.lower():
        fd=str(d.get('forDate'))[:7]; adv.add((d.get('sport'),int(fd[:4]),int(fd[5:7]),plan))
if not adv: print("no Advanced/Pro months owned yet — nothing to do"); sys.exit(0)
con=psycopg2.connect(creds.pg_local(),sslmode='disable'); con.autocommit=True; cur=con.cursor()
cur.execute("""CREATE TABLE IF NOT EXISTS bf_hist_book (sport TEXT, market_id TEXT, market_type TEXT, event_name TEXT, market_time TIMESTAMPTZ, country TEXT, n_winners INT,
  sel TEXT, sel_id BIGINT, ts TIMESTAMPTZ, inplay BOOLEAN, bb1 NUMERIC, bs1 NUMERIC, bb2 NUMERIC, bs2 NUMERIC, bb3 NUMERIC, bs3 NUMERIC, bl1 NUMERIC, ls1 NUMERIC, bl2 NUMERIC, ls2 NUMERIC, bl3 NUMERIC
  CREATE INDEX IF NOT EXISTS bfb_mkt ON bf_hist_book (market_id, ts); CREATE INDEX IF NOT EXISTS bfb_type ON bf_hist_book (sport, market_type, market_time);
  CREATE TABLE IF NOT EXISTS bf_hist_adv_files (path TEXT PRIMARY KEY, loaded_at TIMESTAMPTZ);
  CREATE TABLE IF NOT EXISTS bf_hist_adv_months (sport TEXT, y INT, m INT, status TEXT, files INT, loaded INT, updated TIMESTAMPTZ, PRIMARY KEY (sport,y,m))""")
cur.execute("SELECT sport,y,m,status FROM bf_hist_adv_months"); st={(a,b,c):d for a,b,c,d in cur.fetchall()}
cur.execute("SELECT DISTINCT market_type FROM fair_price_passed WHERE sport='Soccer'"); TYPES=sorted({'MATCH_ODDS','OVER_UNDER_25'}|{t for (t,) in cur.fetchall()})
todo=sorted([a for a in adv if st.get(a[:3]) not in ('DONE','EMPTY')],key=lambda a:(a[0]!='Soccer',-a[1],-a[2]))
...
15:        fd=str(d.get('forDate'))[:7]; adv.add((d.get('sport'),int(fd[:4]),int(fd[5:7]),plan))
18:cur.execute("""CREATE TABLE IF NOT EXISTS bf_hist_book (sport TEXT, market_id TEXT, market_type TEXT, event_name TEXT, market_time TIMESTAMPTZ, country TEXT, n_winners INT,
20:  CREATE INDEX IF NOT EXISTS bfb_mkt ON bf_hist_book (market_id, ts); CREATE INDEX IF NOT EXISTS bfb_type ON bf_hist_book (sport, market_type, market_time);
22:  CREATE TABLE IF NOT EXISTS bf_hist_adv_months (sport TEXT, y INT, m INT, status TEXT, files INT, loaded INT, updated TIMESTAMPTZ, PRIMARY KEY (sport,y,m))""")
23:cur.execute("SELECT sport,y,m,status FROM bf_hist_adv_months"); st={(a,b,c):d for a,b,c,d in cur.fetchall()}
24:cur.execute("SELECT DISTINCT market_type FROM fair_price_passed WHERE sport='Soccer'"); TYPES=sorted({'MATCH_ODDS','OVER_UNDER_25'}|{t for (t,) in cur.fetchall()})
27:def top3(ladder,reverse):
32:def parse(local,sport):
59:                    rows.append((sport,mid,mt,md_.get('eventName'),mtime,md_.get('countryCode'),md_.get('numberOfWinners'),runners.get(sid,str(sid)),sid,datetime.datetime.fromtimestamp(pt/1000,datetime.timezone.utc),i
62:            if x.get('status') in ('WINNER','LOSER'): res.append((sport,str(mid),str(md_.get('eventId')),md_.get('marketType'),runners.get(x['id'],str(x['id'])),x['status'],md_.get('settledTime'),md_.get('status')))
65:for sport,y,m,plan in todo:
67:    mts=TYPES if sport=='Soccer' else []
68:    body={"sport":sport,"plan":plan,"fromDay":1,"fromMonth":m,"fromYear":y,"toDay":calendar.monthrange(y,m)[1],"toMonth":m,"toYear":y,"marketTypesCollection":mts,"countriesCollection":[],"fileTypeCollection":["M"]}
71:    print(f"{sport} {y}-{m:02d} ({plan}): {len(files)} files",flush=True)
72:    if not files: cur.execute("INSERT INTO bf_hist_adv_months VALUES (%s,%s,%s,'EMPTY',0,0,now()) ON CONFLICT (sport,y,m) DO UPDATE SET status='EMPTY', updated=now()",(sport,y,m)); continue
73:    cur.execute("INSERT INTO bf_hist_adv_months VALUES (%s,%s,%s,'LOADING',%s,0,now()) ON CONFLICT (sport,y,m) DO UPDATE SET status='LOADING', files=%s, updated=now()",(sport,y,m,len(files),len(files)))
79:            local='/root/pe-hist/.adv.bz2'; open(local,'wb').write(d.content)
80:            rows,res,md_=parse(local,sport); buf+=rows; rbuf+=res
85:            if rbuf: psycopg2.extras.execute_values(cur,"INSERT INTO bf_hist_result VALUES %s ON CONFLICT DO NOTHING",rbuf,page_size=5000); rbuf=[]
86:            cur.execute("UPDATE bf_hist_adv_months SET loaded=%s, updated=now() WHERE sport=%s AND y=%s AND m=%s",(n,sport,y,m))
88:    if rbuf: psycopg2.extras.execute_values(cur,"INSERT INTO bf_hist_result VALUES %s ON CONFLICT DO NOTHING",rbuf,page_size=5000)
89:    cur.execute("UPDATE bf_hist_adv_months SET status='DONE', loaded=%s, updated=now() WHERE sport=%s AND y=%s AND m=%s",(n,sport,y,m))
91:    os.system(f"cd /root/pe-sports/team && timeout 7000 python3 replay_fills_hist.py {y} {m} >> replay_hist.log 2>&1")
```
## loader logs
```
DB size 106.0 GB
WAITING: box disk under 20 GB free
waiting 10 min
DB size 106.0 GB
WAITING: box disk under 20 GB free
waiting 10 min
DB size 106.0 GB
WAITING: box disk under 20 GB free
waiting 10 min
DB size 106.0 GB
WAITING: box disk under 20 GB free
waiting 10 min
---
GetMyData item keys: ['forDate', 'plan', 'purchaseItemId', 'sport']
no Advanced/Pro months owned yet — nothing to do
GetMyData item keys: ['forDate', 'plan', 'purchaseItemId', 'sport']
no Advanced/Pro months owned yet — nothing to do
GetMyData item keys: ['forDate', 'plan', 'purchaseItemId', 'sport']
no Advanced/Pro months owned yet — nothing to do
GetMyData item keys: ['forDate', 'plan', 'purchaseItemId', 'sport']
no Advanced/Pro months owned yet — nothing to do
GetMyData item keys: ['forDate', 'plan', 'purchaseItemId', 'sport']
no Advanced/Pro months owned yet — nothing to do
GetMyData item keys: ['forDate', 'plan', 'purchaseItemId', 'sport']
no Advanced/Pro months owned yet — nothing to do
```
## keepalive
```
#!/bin/bash
while true; do python3 /root/pe-hist/loader.py >> /root/pe-hist/loader.log 2>&1; sleep 60; done
```
## raw files
```
/root/bfdata
3.4G	/root/bfdata
_filelist.json
_load.log
_load2.log
_pull.log
cricket
ext
greyhound_racing
horse_racing
/root/pe-hist/.adv.bz2
/root/pe-hist/.adv.lock
/root/pe-queue/runner
/root/pe-sports/team
```
