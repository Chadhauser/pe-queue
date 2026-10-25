#!/bin/bash
# 168: UNDERSTAT SHOTS — LOAD + JOIN TO MINUTE PRICES. The browser showed the data now comes from GET /getMatchData/{id} (XHR).
# (a) Test one match from the server (session cookie from the match page first, then the XHR). (b) Load shots for all 3,476 matches
# in understat_matches (1 req/s, resumable, ~1 hour) into understat_shots. (c) Join each Understat match to a bf_hist_price event by
# date (+-1 day) and team-name similarity -> xg_price_map, print coverage per league. This is the first dataset we have with minute-
# level xG/shots AND minute-level prices together. Runs in the background; 169 reports and adds the stats grammar family.
cd /root/pe-scan && cat > understat_shots.py <<'PYFILE'
import re, json, sys, time, requests, psycopg2, psycopg2.extras, unicodedata
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("""CREATE TABLE IF NOT EXISTS understat_shots (understat_id TEXT, shot_id TEXT PRIMARY KEY, minute INT, team_side TEXT, player TEXT, xg NUMERIC, result TEXT, situation TEXT, shot_type TEXT, x NUMERIC, y NUMERIC, last_action TEXT, h_goals INT, a_goals INT)""")
cur.execute("CREATE TABLE IF NOT EXISTS understat_shots_done (understat_id TEXT PRIMARY KEY, n INT, status INT, ts TIMESTAMPTZ DEFAULT now())")
S=requests.Session(); S.headers.update({"User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36","Accept-Language":"en-GB,en;q=0.9"})
def fetch(uid):
    S.get(f"https://understat.com/match/{uid}",timeout=20)      # sets cookies / referer context
    r=S.get(f"https://understat.com/getMatchData/{uid}",headers={"X-Requested-With":"XMLHttpRequest","Referer":f"https://understat.com/match/{uid}","Accept":"application/json, text/javascript, */*; q=0.01"},timeout=20)
    if r.status_code!=200: return r.status_code,None
    try: return 200,r.json()
    except Exception: return 200,None
test=sys.argv[1:2]==['--test']
cur.execute("SELECT understat_id FROM understat_matches m WHERE NOT EXISTS (SELECT 1 FROM understat_shots_done d WHERE d.understat_id=m.understat_id) ORDER BY match_date DESC"); ids=[r[0] for r in cur.fetchall()]
print("to load:",len(ids),flush=True)
ok=0; bad=0
for i,uid in enumerate(ids[:1] if test else ids):
    st,j=fetch(uid)
    if not j or 'shots' not in j:
        cur.execute("INSERT INTO understat_shots_done VALUES (%s,0,%s) ON CONFLICT DO NOTHING",(uid,st)); bad+=1
        if test: print("TEST FAILED status",st,"json keys",list(j.keys()) if j else None); sys.exit(1)
        if bad>=20 and ok==0: print("20 consecutive failures, stopping"); sys.exit(1)
        time.sleep(2); continue
    rows=[]
    for side in ('h','a'):
        for s_ in j['shots'].get(side,[]):
            rows.append((uid,s_['id'],int(float(s_['minute'])),side,s_.get('player'),float(s_['xG']),s_.get('result'),s_.get('situation'),s_.get('shotType'),float(s_['X']),float(s_['Y']),s_.get('lastAction'),int(s_.get('h_goals') or 0),int(s_.get('a_goals') or 0)))
    if rows: psycopg2.extras.execute_values(cur,"INSERT INTO understat_shots VALUES %s ON CONFLICT DO NOTHING",rows)
    cur.execute("INSERT INTO understat_shots_done VALUES (%s,%s,200) ON CONFLICT DO NOTHING",(uid,len(rows))); ok+=1
    if test: print("TEST OK: match",uid,"shots",len(rows),"first:",rows[0][:8]); sys.exit(0)
    if i%100==0: print(f" {i}/{len(ids)} ok {ok} bad {bad}",flush=True)
    time.sleep(1.0)
print("done ok",ok,"bad",bad)
PYFILE
python3 -m py_compile understat_shots.py || exit 1
echo "== (a) endpoint test from the server"; python3 understat_shots.py --test || exit 1
echo "== (b) full load in background"; (nohup python3 understat_shots.py > understat_shots.log 2>&1 &)
echo "== (c) join Understat matches to bf_hist_price events"
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys, re, unicodedata, psycopg2, psycopg2.extras, pandas as pd
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
def norm(s):
    s=unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower().replace('_',' ')
    s=re.sub(r"\b(fc|cf|afc|sc|ac|as|ss|us|sv|vfb|vfl|tsg|fk|club|de|the|athletic|atletico|sporting|real|cd|ud|sd|rcd|calcio|1899|1846|1904|04|05|96|98)\b"," ",s)
    return set(w for w in re.sub(r"[^a-z0-9 ]"," ",s).split() if len(w)>2)
def sim(a,b): A,B=norm(a),norm(b); return len(A&B)/max(1,len(A|B))
U=pd.read_sql("SELECT understat_id, league, match_date::date d, home_team, away_team FROM understat_matches",con)
B=pd.read_sql("SELECT event_id, event_name, country, min(m)::date d FROM bf_hist_price WHERE mkt='MO' AND country IN ('GB','IT','ES','DE','FR') GROUP BY 1,2,3",con)
B=B[B.event_name.str.contains(' v ')]; B['h']=B.event_name.str.split(' v ').str[0]; B['a']=B.event_name.str.split(' v ').str[1]
print("understat matches",len(U),"| betfair events top-5 countries",len(B))
cmap={'EPL':'GB','Serie_A':'IT','La_liga':'ES','Bundesliga':'DE','Ligue_1':'FR'}
rows=[]
for u in U.itertuples():
    cand=B[(B.country==cmap.get(u.league))&((B.d-pd.Timestamp(u.d)).dt.days.abs()<=1)]
    best=None; bs=0; b2=0
    for c in cand.itertuples():
        sc=sim(u.home_team,c.h)+sim(u.away_team,c.a)
        if sc>bs: b2=bs; bs=sc; best=c.event_id
        elif sc>b2: b2=sc
    if best and bs>=1.0 and bs-b2>=0.3: rows.append((u.understat_id,best,round(bs,2)))
cur.execute("CREATE TABLE IF NOT EXISTS xg_price_map (understat_id TEXT PRIMARY KEY, event_id TEXT, score NUMERIC)"); cur.execute("DELETE FROM xg_price_map")
psycopg2.extras.execute_values(cur,"INSERT INTO xg_price_map VALUES %s",rows)
M=pd.DataFrame(rows,columns=['understat_id','event_id','score']).merge(U,on='understat_id')
print("matched",len(M),"of",len(U)); print(M.groupby('league').size().to_string())
print("sample:",M[['league','d','home_team','away_team','event_id','score']].sample(min(6,len(M)),random_state=1).to_string(index=False))
PY
