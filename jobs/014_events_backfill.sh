#!/bin/bash
# 014: MATCH EVENTS BACKFILL (red cards, penalties, VAR, subs) from API-Football for every fixture in fts_advanced_results
# since Aug 2024, so 012's red-card/penalty overshoot test can run. Finds the API key already on this server (the earlier
# goals backfill used it), reports the plan and daily quota from /status, then backfills within quota each run.
# Exits 75 (WAITING, retried every 2 min) while the quota is exhausted; the NEXT job in the queue is not blocked.
cd /root/pe-scan && cat > events_backfill.py <<'PYFILE'
import os, re, sys, glob, json, time, datetime, requests, psycopg2, psycopg2.extras
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
# ---- find the key ----
KEY=None; SRC=None
for f in ['/root/pe-logger/.env','/root/pe-prematch/.env','/root/pe-bot/.env']:
    try:
        for ln in open(f):
            m=re.match(r'^\s*(APIFOOTBALL_KEY|API_FOOTBALL_KEY|APISPORTS_KEY|RAPIDAPI_KEY)\s*=\s*["\']?([A-Za-z0-9]{20,})["\']?',ln)
            if m: KEY,SRC=m.group(2),f
    except FileNotFoundError: pass
if not KEY:
    for f in glob.glob('/root/**/*.py',recursive=True):
        if 'site-packages' in f: continue
        try: s=open(f,errors='ignore').read()
        except Exception: continue
        m=re.search(r'(x-apisports-key|x-rapidapi-key|API_FOOTBALL_KEY|APIFOOTBALL_KEY|APISPORTS_KEY)["\']?\s*[:=]\s*["\']([A-Za-z0-9]{20,})["\']',s,re.I)
        if m: KEY,SRC=m.group(2),f; break
if not KEY: print("WAITING: no API-Football key found on this server (searched .env files and all .py under /root). Peter: echo 'APIFOOTBALL_KEY=<key>' >> /root/pe-logger/.env"); sys.exit(75)
print("key found in",SRC,"(ending ...%s)"%KEY[-4:])
H={"x-apisports-key":KEY}; BASE="https://v3.football.api-sports.io"
st=requests.get(BASE+"/status",headers=H,timeout=30).json()
r=st.get('response') or {}
plan=(r.get('subscription') or {}).get('plan'); lim=(r.get('requests') or {}).get('limit_day'); used=(r.get('requests') or {}).get('current')
print(f"API-Football plan: {plan} | today's requests used/limit: {used}/{lim} | errors: {st.get('errors')}")
if not plan: print("WAITING: /status gave no plan (key rejected?)"); sys.exit(75)
budget=max(0,(lim or 0)-(used or 0)-20)
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("""CREATE TABLE IF NOT EXISTS match_events (fixture_id BIGINT, match_date DATE, league TEXT, home_team TEXT, away_team TEXT,
  minute INT, extra INT, team_side TEXT, type TEXT, detail TEXT, player TEXT, PRIMARY KEY (fixture_id, minute, extra, team_side, type, detail, player));
CREATE TABLE IF NOT EXISTS events_backfill_state (fixture_id BIGINT PRIMARY KEY, match_date DATE, home_team TEXT, away_team TEXT, league TEXT, done BOOLEAN, n_events INT, fetched TIMESTAMPTZ)""")
# ---- fixture list: by league+season from the API, matched to our results by date + first word (same norm as the scans) ----
def norm(s): return re.sub(r'[^a-z]','',(s or '').lower().split(' ')[0])
cur.execute("SELECT DISTINCT competition FROM fts_advanced_results WHERE match_date>='2024-08-01'"); comps=[c[0] for c in cur.fetchall()]
cur.execute("SELECT match_date, competition, home_team, away_team FROM fts_advanced_results WHERE match_date>='2024-08-01'")
OURS={}
for d,lg,h,a in cur.fetchall():
    d=datetime.date.fromisoformat(str(d)[:10]); OURS[(d,norm(h),norm(a))]=(lg,h,a)
print("our fixtures since Aug 2024:",len(OURS),"competitions:",len(comps))
# league ids: resolve once via /leagues?search= and cache in the state table's league column of a sentinel row
cur.execute("CREATE TABLE IF NOT EXISTS apif_league_map (competition TEXT PRIMARY KEY, league_id INT, league_name TEXT, country TEXT)")
cur.execute("SELECT competition, league_id FROM apif_league_map"); LM=dict(cur.fetchall())
ALIAS={'English Premier League':'Premier League','English Championship':'Championship','English League One':'League One','English League Two':'League Two',
 'Scottish Premiership':'Premiership','Spanish Primera Division':'La Liga','Spanish Segunda Division':'Segunda División','Italian Serie A':'Serie A','Italian Serie B':'Serie B',
 'German Bundesliga':'Bundesliga','German 2. Bundesliga':'2. Bundesliga','French Ligue 1':'Ligue 1','French Ligue 2':'Ligue 2','Dutch Eredivisie':'Eredivisie',
 'Belgian Pro League':'Jupiler Pro League','Portuguese Primeira Liga':'Primeira Liga','Turkish Super Lig':'Süper Lig','Greek Super League':'Super League 1',
 'Swiss Super League':'Super League','Austrian Bundesliga':'Bundesliga','Danish Superliga':'Superliga','Norwegian Eliteserien':'Eliteserien','Swedish Allsvenskan':'Allsvenskan',
 'Japanese J-League':'J1 League','US MLS':'Major League Soccer','Australian A-League':'A-League','Argentine Primera Division':'Liga Profesional Argentina','Brazilian Serie A':'Serie A','Polish Ekstraklasa':'Ekstraklasa','Czech First League':'Czech Liga'}
COUNTRY_HINT={'English':'England','Scottish':'Scotland','Spanish':'Spain','Italian':'Italy','German':'Germany','French':'France','Dutch':'Netherlands','Belgian':'Belgium','Portuguese':'Portugal','Turkish':'Turkey','Greek':'Greece','Swiss':'Switzerland','Austrian':'Austria','Danish':'Denmark','Norwegian':'Norway','Swedish':'Sweden','Japanese':'Japan','US':'USA','Australian':'Australia','Argentine':'Argentina','Brazilian':'Brazil','Polish':'Poland','Czech':'Czech-Republic'}
calls=0
def get(path,**params):
    global calls
    calls+=1
    if calls>budget: raise RuntimeError("quota")
    r=requests.get(BASE+path,headers=H,params=params,timeout=30).json()
    if r.get('errors') and not isinstance(r['errors'],list): print("API error",path,params,r['errors']);
    return r.get('response') or []
try:
    for c in comps:
        if c in LM: continue
        name=ALIAS.get(c,c); country=next((v for k,v in COUNTRY_HINT.items() if c.startswith(k)),None)
        res=get('/leagues',search=name) if not country else get('/leagues',name=name,country=country)
        pick=None
        for L in res:
            if L['league']['type']=='League' and (not country or L['country']['name'].lower()==country.lower()): pick=L; break
        if not pick and res: pick=res[0]
        if pick:
            cur.execute("INSERT INTO apif_league_map VALUES (%s,%s,%s,%s) ON CONFLICT (competition) DO NOTHING",(c,pick['league']['id'],pick['league']['name'],pick['country']['name'])); LM[c]=pick['league']['id']
            print("league map",c,"->",pick['league']['id'],pick['league']['name'],pick['country']['name'])
        else: print("league NOT FOUND in API-Football:",c)
    # fixtures per league-season (1 call each), then events per fixture (1 call each)
    cur.execute("SELECT fixture_id FROM events_backfill_state WHERE done"); DONE={r[0] for r in cur.fetchall()}
    cur.execute("SELECT fixture_id, match_date, home_team, away_team, league FROM events_backfill_state WHERE NOT done"); TODO=cur.fetchall()
    if not TODO and not DONE:
        for c,lid in LM.items():
            for season in (2024,2025):
                for fx in get('/fixtures',league=lid,season=season,status='FT-AET-PEN'):
                    d=datetime.date.fromisoformat(fx['fixture']['date'][:10]); h=fx['teams']['home']['name']; a=fx['teams']['away']['name']
                    key=next((k for k in ((d,norm(h),norm(a)),(d-datetime.timedelta(days=1),norm(h),norm(a)),(d+datetime.timedelta(days=1),norm(h),norm(a))) if k in OURS),None)
                    if not key: continue
                    cur.execute("INSERT INTO events_backfill_state (fixture_id,match_date,home_team,away_team,league,done) VALUES (%s,%s,%s,%s,%s,false) ON CONFLICT DO NOTHING",(fx['fixture']['id'],key[0],OURS[key][1],OURS[key][2],OURS[key][0]))
        cur.execute("SELECT fixture_id, match_date, home_team, away_team, league FROM events_backfill_state WHERE NOT done"); TODO=cur.fetchall()
        print("fixtures matched to our results:",len(TODO),"of",len(OURS))
    for fid,d,h,a,lg in TODO:
        evs=get('/fixtures/events',fixture=fid); rows=[]
        for e in evs:
            side='H' if e['team']['name']==h or norm(e['team']['name'])==norm(h) else 'A'
            rows.append((fid,d,lg,h,a,e['time']['elapsed'] or 0,e['time'].get('extra') or 0,side,e.get('type') or '',e.get('detail') or '',(e.get('player') or {}).get('name') or ''))
        if rows: psycopg2.extras.execute_values(cur,"INSERT INTO match_events VALUES %s ON CONFLICT DO NOTHING",rows)
        cur.execute("UPDATE events_backfill_state SET done=true, n_events=%s, fetched=NOW() WHERE fixture_id=%s",(len(rows),fid))
        time.sleep(0.25)
except RuntimeError:
    cur.execute("SELECT count(*) FILTER (WHERE done), count(*) FROM events_backfill_state"); print("QUOTA for today used. progress done/total:",cur.fetchone()); sys.exit(75)
cur.execute("SELECT count(*) FILTER (WHERE done), count(*) FROM events_backfill_state"); print("BACKFILL COMPLETE done/total:",cur.fetchone())
cur.execute("SELECT type, detail, count(*) FROM match_events GROUP BY 1,2 ORDER BY 3 DESC LIMIT 20"); print("event counts:",cur.fetchall())
PYFILE
python3 events_backfill.py; rc=$?
exit $rc
