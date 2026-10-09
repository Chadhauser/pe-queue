#!/bin/bash
# 010: pull the missing goal markets (needs a valid BF_SSOID in /root/pe-logger/.env) and load them into bf_hist_price
# using each event's already-calibrated half-time offset. Then 011 reruns the state scan over all markets.
# Token: the Historic Data API takes the same SSO token as the exchange API. Get one with the bot's own login
# (bot_core APP_KEY/USERNAME/PASSWORD) and write it to .env, so nobody has to copy a cookie. Exit 75 (WAITING) if that fails.
python3 - <<'PY' || exit 75
import sys, re, requests
sys.path.insert(0,'/root/pe-bot'); import bot_core
def env(f):
    d={}
    try:
        for ln in open(f):
            if '=' in ln and not ln.startswith('#'): k,v=ln.strip().split('=',1); d[k.strip()]=v.strip().strip('"').strip("'")
    except FileNotFoundError: pass
    return d
E={}; [E.update(env(f)) for f in ('/root/pe-logger/.env','/root/pe-prematch/.env','/root/pe-bot/.env')]
APP=getattr(bot_core,'APP_KEY',None) or E.get('APP_KEY') or E.get('BF_APP_KEY')
U=getattr(bot_core,'USERNAME',None) or E.get('USERNAME') or E.get('BF_USERNAME')
P=getattr(bot_core,'PASSWORD',None) or E.get('PASSWORD') or E.get('BF_PASSWORD')
def ok(tok): return requests.get("https://historicdata.betfair.com/api/GetMyData",headers={"ssoid":tok},timeout=20).status_code==200
tok=E.get('BF_SSOID')
if tok and tok!='VALUE' and ok(tok): print("existing token OK"); sys.exit(0)
if not (APP and U and P): print("WAITING: no Betfair credentials found for SSO login"); sys.exit(1)
r=requests.post("https://identitysso.betfair.com/api/login",data={"username":U,"password":P},headers={"X-Application":APP,"Accept":"application/json"},timeout=20).json()
if r.get('status')!='SUCCESS': print("WAITING: SSO login failed:",r.get('error')); sys.exit(1)
tok=r['token']
if not ok(tok): print("WAITING: SSO token not accepted by Historic Data API (HTTP != 200)"); sys.exit(1)
s=open('/root/pe-logger/.env').read() if __import__('os').path.exists('/root/pe-logger/.env') else ''
s=re.sub(r'^BF_SSOID=.*$','BF_SSOID='+tok,s,flags=re.M) if re.search(r'^BF_SSOID=',s,re.M) else s.rstrip('\n')+'\nBF_SSOID='+tok+'\n'
open('/root/pe-logger/.env','w').write(s); print("token obtained by SSO login and written to .env")
PY
cd /root/pe-logger && python3 bf_hist_pull_ext.py || { echo "PULL FAILED after a valid token check"; exit 1; }
cd /root/pe-scan && cat > load_ext.py <<'PYFILE'
import os, bz2, json, glob, sys, datetime, psycopg2, psycopg2.extras
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
MAP={'OVER_UNDER_15':'OU15','OVER_UNDER_35':'OU35','BOTH_TEAMS_TO_SCORE':'BTTS','FIRST_HALF_GOALS_05':'FH05','FIRST_HALF_GOALS_15':'FH15'}
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("SELECT event_id, max(ht_offset), bool_or(calibrated), min(event_name), min(hw), min(aw), min(country) FROM bf_hist_price GROUP BY event_id")
EV={r[0]:r[1:] for r in cur.fetchall()}
cur.execute("DELETE FROM bf_hist_price WHERE mkt IN ('OU15','OU35','BTTS','FH05','FH15')")
files=glob.glob('/root/bfdata/ext/**/*.bz2',recursive=True)+glob.glob('/root/bfdata/ext/*.bz2')
print("ext files on disk",len(files),flush=True)
rows=[]; loaded=0; skipped=0
def sel_name(mt,name):
    n=name.lower()
    if mt=='BOTH_TEAMS_TO_SCORE': return 'YES' if n.startswith('y') else 'NO'
    return 'OVER' if n.startswith('over') else 'UNDER'
for i,path in enumerate(files):
    try: lines=bz2.open(path,'rt').read().split('\n')
    except Exception: continue
    md=None; runners={}; ltp={}; ko=None; per_min={}
    for ln in lines:
        if not ln: continue
        try: o=json.loads(ln)
        except: continue
        pt=o.get('pt')
        for mc in o.get('mc',[]):
            if 'marketDefinition' in mc:
                m=mc['marketDefinition']
                if m.get('marketType') not in MAP: md=False; break
                md=m; runners.update({r['id']:r['name'] for r in m.get('runners',[])})
                if m.get('inPlay') and ko is None: ko=pt
            if ko is None: continue
            for rc in mc.get('rc',[]):
                if 'ltp' in rc and rc['id'] in runners:
                    bfmin=int((pt-ko)/60000); per_min[(rc['id'],bfmin)]=(pt,rc['ltp'])
        if md is False: break
    if not md or ko is None: skipped+=1; continue
    eid=str(md.get('eventId')); ev=EV.get(eid)
    if not ev: skipped+=1; continue
    hto,cal,ename,hw,aw,country=ev; hto=float(hto) if hto is not None else 19.5
    mkt=MAP[md['marketType']]
    for (sid,bfmin),(pt,p) in per_min.items():
        # Betfair clock minute -> match minute: first half as-is; second half subtract the calibrated offset; drop the break
        if bfmin<=45: minute=bfmin
        elif bfmin<45+hto: continue
        else: minute=int(bfmin-hto)
        if minute>100: continue
        rows.append((eid,ename,hw,aw,country,datetime.datetime.utcfromtimestamp(pt/1000).replace(tzinfo=datetime.timezone.utc),minute,mkt,sel_name(md['marketType'],runners[sid]),p,hto,cal))
    loaded+=1
    if len(rows)>=50000:
        psycopg2.extras.execute_values(cur,"INSERT INTO bf_hist_price (event_id,event_name,hw,aw,country,m,minute,mkt,sel,ltp,ht_offset,calibrated) VALUES %s",rows,page_size=5000); rows=[]
    if i%2000==0: print("files",i,"loaded",loaded,"skipped",skipped,flush=True)
if rows: psycopg2.extras.execute_values(cur,"INSERT INTO bf_hist_price (event_id,event_name,hw,aw,country,m,minute,mkt,sel,ltp,ht_offset,calibrated) VALUES %s",rows,page_size=5000)
cur.execute("SELECT mkt, count(DISTINCT event_id), count(*) FROM bf_hist_price GROUP BY mkt ORDER BY mkt")
print("bf_hist_price by market (events, rows):",cur.fetchall())
PYFILE
python3 load_ext.py
