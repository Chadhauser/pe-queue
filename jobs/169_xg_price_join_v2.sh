#!/bin/bash
# 169: re-run the Understat<->Betfair match join with team aliases (Man Utd, PSG, Wolves, Athletic Bilbao were missed by 168) and print coverage.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys, re, unicodedata, psycopg2, psycopg2.extras, pandas as pd
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
ALIAS={'utd':'united','man':'manchester','psg':'paris saint germain','wolves':'wolverhampton','bilbao':'club','spurs':'tottenham','gladbach':'monchengladbach','leverkusen':'bayer leverkusen','koln':'cologne','mainz':'mainz','st':'saint','om':'marseille','ol':'lyon','ac':'','dortmund':'borussia dortmund','inter':'internazionale','milan':'milan','nice':'nice','monaco':'monaco'}
def norm(s):
    s=unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower().replace('_',' ')
    s=' '.join(ALIAS.get(w,w) for w in re.sub(r"[^a-z0-9 ]"," ",s).split())
    s=re.sub(r"\b(fc|cf|afc|sc|ac|as|ss|us|sv|vfb|vfl|tsg|fk|club|de|the|atletico|sporting|real|cd|ud|sd|rcd|calcio|1899|1846|1904|04|05|96|98)\b"," ",s)
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
