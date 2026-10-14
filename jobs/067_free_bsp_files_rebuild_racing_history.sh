#!/bin/bash
# 067: REBUILD THE 164,900-RUNNER RACING HISTORY FOR FREE. Betfair publishes daily BSP/result files (the dwbfpricesukwin*.csv Peter
# once uploaded) at promo.betfair.com for every day. Pull UK + IE WIN and PLACE files from 1 Jan 2022 to yesterday into racing_bsp
# (event_dt, menu_hint, event_name, selection_id, selection_name, win_lose, bsp, ppwap, morningwap, ppmax, ppmin, ipmax, ipmin,
# morning/pp/ip traded volumes). ipmin vs bsp is the in-play 'shortened 25%+' signal from the earlier validated work. Resumable.
cd /root && python3 - <<'PY'
import io, sys, time, datetime, requests, psycopg2, psycopg2.extras, pandas as pd
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("""CREATE TABLE IF NOT EXISTS racing_bsp (country TEXT, market TEXT, event_id BIGINT, menu_hint TEXT, event_name TEXT, event_dt TIMESTAMP, selection_id BIGINT, selection_name TEXT,
  win_lose INT, bsp NUMERIC, ppwap NUMERIC, morningwap NUMERIC, ppmax NUMERIC, ppmin NUMERIC, ipmax NUMERIC, ipmin NUMERIC, morning_vol NUMERIC, pp_vol NUMERIC, ip_vol NUMERIC);
  CREATE INDEX IF NOT EXISTS racing_bsp_dt ON racing_bsp (event_dt); CREATE TABLE IF NOT EXISTS racing_bsp_files (fname TEXT PRIMARY KEY, rows INT, loaded_at TIMESTAMPTZ)""")
cur.execute("SELECT fname FROM racing_bsp_files"); done={r[0] for r in cur.fetchall()}
d=datetime.date(2022,1,1); end=datetime.date.today()-datetime.timedelta(days=1); t0=time.time(); n=0
COLS=['event_id','menu_hint','event_name','event_dt','selection_id','selection_name','win_lose','bsp','ppwap','morningwap','ppmax','ppmin','ipmax','ipmin','morningtradedvol','pptradedvol','iptradedvol']
while d<=end:
    if time.time()-t0>8*60: print("time budget used; continuing next cycle"); sys.exit(75)
    for country in ('uk','ire'):
        for market in ('win','place'):
            fname=f"dwbfprices{country}{market}{d:%d%m%Y}.csv"
            if fname in done: continue
            try: r=requests.get(f"https://promo.betfair.com/betfairsp/prices/{fname}",timeout=30)
            except Exception as e: print("fetch error",fname,repr(e)[:60]); continue
            if r.status_code!=200 or len(r.content)<50:
                cur.execute("INSERT INTO racing_bsp_files VALUES (%s,0,NOW()) ON CONFLICT DO NOTHING",(fname,)); continue
            try: df=pd.read_csv(io.StringIO(r.text))
            except Exception as e: print("parse error",fname,repr(e)[:60]); continue
            df.columns=[c.strip().lower() for c in df.columns]
            for c in COLS:
                if c not in df.columns: df[c]=None
            rows=[]
            for x in df[COLS].itertuples(index=False):
                try: dt=datetime.datetime.strptime(str(x.event_dt).strip(),'%d-%m-%Y %H:%M')
                except Exception: dt=None
                rows.append((country,market,int(x.event_id) if pd.notna(x.event_id) else None,x.menu_hint,x.event_name,dt,int(x.selection_id) if pd.notna(x.selection_id) else None,x.selection_name,
                             int(x.win_lose) if pd.notna(x.win_lose) else None,*[(float(v) if pd.notna(v) else None) for v in (x.bsp,x.ppwap,x.morningwap,x.ppmax,x.ppmin,x.ipmax,x.ipmin,x.morningtradedvol,x.pptradedvol,x.iptradedvol)]))
            psycopg2.extras.execute_values(cur,"INSERT INTO racing_bsp VALUES %s",rows,page_size=2000)
            cur.execute("INSERT INTO racing_bsp_files VALUES (%s,%s,NOW()) ON CONFLICT DO NOTHING",(fname,len(rows))); n+=1
    d+=datetime.timedelta(days=1)
    if n and n%100==0: print("files",n,"up to",d,flush=True)
cur.execute("SELECT country, market, count(*), min(event_dt)::date, max(event_dt)::date FROM racing_bsp GROUP BY 1,2 ORDER BY 1,2"); print("racing_bsp:",cur.fetchall())
PY
