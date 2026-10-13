#!/bin/bash
# 047: Understat league pages no longer embed the fixture list (18KB shell page). Match pages DO embed shotsData (035 proved it).
# So walk match ids directly: 25500-30500 covers 2024/25 and 2025/26 for the top-5 leagues; the page title carries league+season.
# ~5,000 requests at 1/s. Resumable (skips ids already seen). Then 033 runs on its own.
cd /root/pe-scan && cat > understat_by_id.py <<'PYFILE'
import re, json, sys, time, requests, psycopg2, psycopg2.extras
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("CREATE TABLE IF NOT EXISTS understat_seen (understat_id TEXT PRIMARY KEY, league TEXT, season TEXT, ok BOOLEAN)")
cur.execute("ALTER TABLE understat_shots ADD COLUMN IF NOT EXISTS x NUMERIC, ADD COLUMN IF NOT EXISTS y NUMERIC, ADD COLUMN IF NOT EXISTS last_action TEXT, ADD COLUMN IF NOT EXISTS h_goals INT, ADD COLUMN IF NOT EXISTS a_goals INT")
H={"User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124.0 Safari/537.36","Accept-Language":"en-GB,en;q=0.9","Referer":"https://understat.com/"}
def jsvar(html,name):
    i=html.find(name)
    if i<0: return None
    j=html.find('JSON.parse(',i)
    if j<0 or j-i>200: return None
    j+=len('JSON.parse('); q=html[j]; k=j+1; buf=[]
    while k<len(html):
        ch=html[k]
        if ch=='\\': buf.append(html[k:k+2]); k+=2; continue
        if ch==q: break
        buf.append(ch); k+=1
    s=''.join(buf)
    try: s=s.encode('utf-8').decode('unicode_escape')
    except Exception: pass
    try: return json.loads(s)
    except Exception: return None
cur.execute("SELECT understat_id FROM understat_seen"); seen={r[0] for r in cur.fetchall()}
LG={'EPL':'EPL','La liga':'La_liga','Bundesliga':'Bundesliga','Serie A':'Serie_A','Ligue 1':'Ligue_1'}
ok=0; miss=0; t0=time.time()
for mid in range(25500,30501):
    uid=str(mid)
    if uid in seen: continue
    try:
        r=requests.get(f"https://understat.com/match/{uid}",headers=H,timeout=30)
    except Exception as e:
        print("net",uid,repr(e)[:60],flush=True); time.sleep(10); continue
    if r.status_code!=200:
        cur.execute("INSERT INTO understat_seen VALUES (%s,NULL,NULL,false) ON CONFLICT DO NOTHING",(uid,)); miss+=1
        if r.status_code in (403,429): print("blocked",r.status_code,flush=True); time.sleep(60)
        time.sleep(1); continue
    t=re.findall(r'<title>(.*?)</title>',r.text,re.S); t=t[0] if t else ''
    m=re.search(r'\|\s*(EPL|La liga|Bundesliga|Serie A|Ligue 1)\s*\|\s*(\d{4})/(\d{4})',t)
    if not m: cur.execute("INSERT INTO understat_seen VALUES (%s,NULL,NULL,false) ON CONFLICT DO NOTHING",(uid,)); miss+=1; time.sleep(1); continue
    lg=LG[m.group(1)]; season=m.group(2)
    md=jsvar(r.text,'match_info') or {}
    sd=jsvar(r.text,'shotsData') or {}
    teams=re.match(r'(.*?)\s+(\d+)\s*-\s*(\d+)\s+(.*?)\s*\(',t)
    home,away,hg,ag=(teams.group(1),teams.group(4),int(teams.group(2)),int(teams.group(3))) if teams else (md.get('team_h'),md.get('team_a'),None,None)
    date=(md.get('date') or '')[:10] or None
    cur.execute("""INSERT INTO understat_matches (understat_id,league,season,match_date,home_team,away_team,home_goals,away_goals,home_xg,away_xg,collected_at)
                   VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,NOW()) ON CONFLICT DO NOTHING""",(uid,lg,season,date,home,away,hg,ag,float(md.get('h_xg') or 0) or None,float(md.get('a_xg') or 0) or None))
    rows=[]
    for side in ('h','a'):
        for s in sd.get(side,[]):
            rows.append((uid,str(s['id']),int(s['minute']),'H' if side=='h' else 'A',s.get('player'),float(s['xG']),s.get('result'),s.get('situation'),s.get('shotType'),float(s.get('X') or 0),float(s.get('Y') or 0),s.get('lastAction'),int(s.get('h_goals') or 0),int(s.get('a_goals') or 0)))
    if rows: psycopg2.extras.execute_values(cur,"INSERT INTO understat_shots (understat_id,shot_id,minute,team_side,player,xg,result,situation,shot_type,x,y,last_action,h_goals,a_goals) VALUES %s ON CONFLICT DO NOTHING",rows)
    cur.execute("INSERT INTO understat_seen VALUES (%s,%s,%s,true) ON CONFLICT DO NOTHING",(uid,lg,season)); ok+=1
    if ok%100==0: print(f"loaded {ok} matches, skipped {miss}, {int(time.time()-t0)}s",flush=True)
    time.sleep(1.0)
cur.execute("SELECT league, season, count(*) FROM understat_matches GROUP BY 1,2 ORDER BY 1,2"); print(cur.fetchall())
cur.execute("SELECT count(*), count(DISTINCT understat_id) FROM understat_shots"); print("shots rows, matches:",cur.fetchone())
PYFILE
python3 understat_by_id.py
