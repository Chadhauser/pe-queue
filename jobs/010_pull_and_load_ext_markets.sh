#!/bin/bash
# 010: pull the missing goal markets (needs a valid BF_SSOID in /root/pe-logger/.env) and load them into bf_hist_price
# using each event's already-calibrated half-time offset. Then 011 reruns the state scan over all markets.
# Gate: a valid Historic Data token. Until Peter puts one in /root/pe-logger/.env this job exits 75 (= WAITING, retried every 2 min).
TOK=$(grep -E '^BF_SSOID=' /root/pe-logger/.env 2>/dev/null | cut -d= -f2- | tr -d '"\x27 ')
if [ -z "$TOK" ]; then echo "WAITING: no BF_SSOID in /root/pe-logger/.env"; exit 75; fi
CODE=$(curl -s -o /dev/null -w '%{http_code}' -H "ssoid: $TOK" -H "Content-Type: application/json" https://historicdata.betfair.com/api/GetMyData)
if [ "$CODE" != "200" ]; then echo "WAITING: Historic Data API returned HTTP $CODE for the token in .env (expired? refresh it)"; exit 75; fi
echo "token OK (HTTP 200)"
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
