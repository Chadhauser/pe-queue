#!/bin/bash
# 184: (181 crashed on fixtures without a result — NaN goals; now filtered.) Then restarts the sweep. TRUE RESULTS FOR THE PRICE FILE. Settling from prices (final collapse) or from detected goals both proved error-prone (90%
# result accuracy on a 50-game check). football_matches holds FT and HT scores + shots for ~15k games Jul 2024 -> May 2026 across 20
# European leagues, understat_matches holds FT scores for the top five. Join both to bf_hist_price events by date (+-1 day), country
# and team-name similarity (alias-aware) -> event_results(event_id, fthg, ftag, hthg, htag, hs, as_, hst, ast, source). Coverage printed
# per country. The sweep (182) then settles FT/NG only from this table and checks its detected goal count against the true total.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys, re, unicodedata, psycopg2, psycopg2.extras, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
ALIAS={'utd':'united','man':'manchester','psg':'paris saint germain','wolves':'wolverhampton','spurs':'tottenham','gladbach':'monchengladbach','leverkusen':'bayer leverkusen','st':'saint','dortmund':'borussia dortmund','inter':'internazionale','sheff':'sheffield','nottm':'nottingham','forest':'nottingham forest','qpr':'queens park rangers','mk':'milton keynes','ath':'athletic','atl':'atletico','ath.':'athletic','dep':'deportivo','spm':'sporting','utrecht':'utrecht','nac':'nac breda','psv':'psv eindhoven','az':'az alkmaar','ado':'ado den haag','rkc':'rkc waalwijk','sc':'','fc':''}
def norm(s):
    s=unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower().replace('_',' ').replace('&','and')
    s=' '.join(ALIAS.get(w,w) for w in re.sub(r"[^a-z0-9 ]"," ",s).split())
    s=re.sub(r"\b(fc|cf|afc|sc|ac|as|ss|us|sv|vfb|vfl|tsg|fk|club|de|the|atletico|sporting|real|cd|ud|sd|rcd|calcio|1899|1846|1904|04|05|96|98)\b"," ",s)
    toks=set(w for w in s.split() if len(w)>2)
    return toks
def sim(a,b):
    A,B=norm(a),norm(b)
    if not A or not B: return 1.0 if str(a).lower().strip()==str(b).lower().strip() else 0.0
    return len(A&B)/max(1,len(A|B))
B=pd.read_sql("SELECT event_id, event_name, country, min(m)::date d FROM bf_hist_price WHERE mkt='MO' GROUP BY 1,2,3",con)
B=B[B.event_name.str.contains(' v ')].copy(); B['d']=pd.to_datetime(B.d); B['h']=B.event_name.str.split(' v ').str[0].str.strip(); B['a']=B.event_name.str.split(' v ').str[1].str.strip()
print("betfair events",len(B)); print("by country:",B.country.value_counts().head(15).to_dict())
F=pd.read_sql("SELECT league_code, date, home_team, away_team, fthg, ftag, hthg, htag, hs, as_, hst, ast FROM football_matches WHERE date>='2024-07-01' AND fthg IS NOT NULL AND ftag IS NOT NULL",con); F['d']=pd.to_datetime(F.date)
LC={'E0':'GB','E1':'GB','E2':'GB','E3':'GB','EC':'GB','SC0':'GB','SC1':'GB','SC2':'GB','SC3':'GB','SP1':'ES','SP2':'ES','I1':'IT','I2':'IT','D1':'DE','D2':'DE','F1':'FR','F2':'FR','N1':'NL','P1':'PT','B1':'BE','T1':'TR','G1':'GR'}
F['country']=F.league_code.map(LC)
U=pd.read_sql("SELECT understat_id::text understat_id, league, match_date::date d, home_team, away_team, home_goals, away_goals FROM understat_matches WHERE home_goals IS NOT NULL AND away_goals IS NOT NULL",con); U['d']=pd.to_datetime(U.d)
U['country']=U.league.map({'EPL':'GB','Serie_A':'IT','La_liga':'ES','Bundesliga':'DE','Ligue_1':'FR'})
def match(src,label):
    rows=[]; used=set()
    for c in src.country.dropna().unique():
        Bc=B[B.country==c]; Sc=src[src.country==c]
        if Bc.empty: continue
        Bc=Bc.sort_values('d')
        for u in Sc.itertuples():
            cand=Bc[(Bc.d-u.d).dt.days.abs()<=1]
            best=None; bs=0; b2=0
            for e in cand.itertuples():
                sc=sim(u.home_team,e.h)+sim(u.away_team,e.a)
                if sc>bs: b2=bs; bs=sc; best=e
                elif sc>b2: b2=sc
            if best is not None and bs>=1.0 and bs-b2>=0.3 and best.event_id not in used:
                used.add(best.event_id); rows.append((best.event_id,u,label,round(bs,2)))
    return rows
rows=[]
for eid,u,label,sc in match(F,'football_matches'): rows.append((eid,int(u.fthg),int(u.ftag),(int(u.hthg) if pd.notna(u.hthg) else None),(int(u.htag) if pd.notna(u.htag) else None),(int(u.hs) if pd.notna(u.hs) else None),(int(u.as_) if pd.notna(u.as_) else None),(int(u.hst) if pd.notna(u.hst) else None),(int(u.ast) if pd.notna(u.ast) else None),label,sc))
have=set(r[0] for r in rows)
for eid,u,label,sc in match(U,'understat'):
    if eid not in have: rows.append((eid,int(u.home_goals),int(u.away_goals),None,None,None,None,None,None,label,sc)); have.add(eid)
cur.execute("DROP TABLE IF EXISTS event_results"); cur.execute("CREATE TABLE event_results (event_id TEXT PRIMARY KEY, fthg INT, ftag INT, hthg INT, htag INT, hs INT, as_ INT, hst INT, ast INT, source TEXT, score NUMERIC)")
psycopg2.extras.execute_values(cur,"INSERT INTO event_results VALUES %s ON CONFLICT DO NOTHING",rows,page_size=2000)
R=pd.DataFrame(rows,columns=['event_id','fthg','ftag','hthg','htag','hs','as_','hst','ast','source','score']).merge(B[['event_id','country']],on='event_id')
print("event_results rows:",len(R),"| by source:",R.source.value_counts().to_dict()); print("coverage by country (matched / betfair events):")
cov=R.groupby('country').size().to_frame('matched').join(B.groupby('country').size().to_frame('events')); cov['pct']=(cov.matched/cov.events).round(2); print(cov.sort_values('events',ascending=False).head(15).to_string())
# cross-check: where both sources matched the same event, do the scores agree?
X=pd.DataFrame([(eid,int(u.fthg),int(u.ftag)) for eid,u,l,s in match(F,'fm')],columns=['event_id','h1','a1']).merge(pd.DataFrame([(eid,int(u.home_goals),int(u.away_goals)) for eid,u,l,s in match(U,'us')],columns=['event_id','h2','a2']),on='event_id')
print("both sources on same event:",len(X),"| score agreement:",f"{((X.h1==X.h2)&(X.a1==X.a2)).mean():.1%}" if len(X) else "n/a")
PY

cd /root/pe-factory/v4 && pkill -f sport_sweep.py; sleep 1; (nohup timeout 10000 python3 sport_sweep.py > sport_sweep.log 2>&1 &); echo "sweep restarted with true results"
