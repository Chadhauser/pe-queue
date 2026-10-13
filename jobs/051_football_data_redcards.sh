#!/bin/bash
# 051: RED CARDS (and shots, corners, fouls, closing odds) — free, match-level, from football-data.co.uk. The minute-level
# events backfill (014) is stuck WAITING because the API-Football key on this server is rejected; this closes the gap at match
# level for nothing. 22 leagues x 5 seasons (2021/22 - 2025/26), ~40k matches. Table fd_matches (one row per match, raw row kept
# as JSON so no column is ever lost). Then prints: red-card frequency by league, how often a red card precedes a result the
# pre-match odds did not expect (the overshoot question at match level), and which leagues see most cards (where a minute-level
# feed would be worth buying).
cd /root/pe-scan && cat > fd_load.py <<'PYFILE'
import io, sys, json, time, datetime, requests, psycopg2, psycopg2.extras, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("""CREATE TABLE IF NOT EXISTS fd_matches (div TEXT, season TEXT, match_date DATE, home_team TEXT, away_team TEXT, fthg INT, ftag INT, hthg INT, htag INT,
  hs INT, as_ INT, hst INT, ast INT, hc INT, ac INT, hf INT, af INT, hy INT, ay INT, hr INT, ar INT, b365h NUMERIC, b365d NUMERIC, b365a NUMERIC, b365_o25 NUMERIC, b365_u25 NUMERIC,
  psch NUMERIC, pscd NUMERIC, psca NUMERIC, raw JSONB, PRIMARY KEY (div,season,match_date,home_team,away_team))""")
DIVS=['E0','E1','E2','E3','EC','SC0','SC1','D1','D2','I1','I2','SP1','SP2','F1','F2','N1','B1','P1','T1','G1']
SEASONS=['2122','2223','2324','2425','2526']
H={"User-Agent":"Mozilla/5.0"}
def num(v):
    try:
        if v is None or (isinstance(v,float) and np.isnan(v)) or str(v).strip()=='': return None
        return float(v)
    except Exception: return None
def i(v): x=num(v); return None if x is None else int(x)
tot=0
for s in SEASONS:
    for d in DIVS:
        url=f"https://www.football-data.co.uk/mmz4281/{s}/{d}.csv"
        try:
            r=requests.get(url,headers=H,timeout=30)
            if r.status_code!=200: print(d,s,"HTTP",r.status_code,flush=True); continue
            df=pd.read_csv(io.StringIO(r.content.decode('latin-1')),on_bad_lines='skip')
        except Exception as e: print(d,s,"error",repr(e)[:80],flush=True); continue
        df=df.dropna(subset=['Date','HomeTeam','AwayTeam'])
        rows=[]
        for _,x in df.iterrows():
            try: dt=datetime.datetime.strptime(str(x['Date']).strip(),'%d/%m/%Y').date()
            except Exception:
                try: dt=datetime.datetime.strptime(str(x['Date']).strip(),'%d/%m/%y').date()
                except Exception: continue
            raw={k:(None if (isinstance(v,float) and np.isnan(v)) else v) for k,v in x.items()}
            g=lambda k: x[k] if k in df.columns else None
            rows.append((d,s,dt,str(x['HomeTeam']).strip(),str(x['AwayTeam']).strip(),i(g('FTHG')),i(g('FTAG')),i(g('HTHG')),i(g('HTAG')),i(g('HS')),i(g('AS')),i(g('HST')),i(g('AST')),
                         i(g('HC')),i(g('AC')),i(g('HF')),i(g('AF')),i(g('HY')),i(g('AY')),i(g('HR')),i(g('AR')),num(g('B365H')),num(g('B365D')),num(g('B365A')),num(g('B365>2.5')),num(g('B365<2.5')),
                         num(g('PSCH')),num(g('PSCD')),num(g('PSCA')),json.dumps(raw,default=str)))
        if rows:
            psycopg2.extras.execute_values(cur,"INSERT INTO fd_matches VALUES %s ON CONFLICT DO NOTHING",rows)
        tot+=len(rows); print(d,s,len(rows),flush=True); time.sleep(0.5)
print("rows processed",tot)
pd.set_option('display.width',240)
M=pd.read_sql("SELECT div,season,hr,ar,fthg,ftag,hthg,htag,b365h,b365d,b365a FROM fd_matches WHERE hr IS NOT NULL",con)
print("matches with card data",len(M))
M['red']=(M.hr.fillna(0)+M.ar.fillna(0))>0
print("\n=== red-card match rate by league (share of matches with any red) ==="); print(M.groupby('div').red.agg(['size','mean']).round(3).sort_values('mean',ascending=False).to_string())
# match-level overshoot proxy: when a side gets a red and the pre-match fav was the OTHER side, how often does the fav still win vs its implied prob
M['fav']=np.where(M.b365h<M.b365a,'H','A'); M['fav_p']=1/np.where(M.fav=='H',M.b365h,M.b365a)
M['fav_won']=np.where(M.fav=='H',M.fthg>M.ftag,M.ftag>M.fthg)
M['dog_red']=np.where(M.fav=='H',M.ar.fillna(0)>0,M.hr.fillna(0)>0); M['fav_red']=np.where(M.fav=='H',M.hr.fillna(0)>0,M.ar.fillna(0)>0)
print("\n=== favourite win rate vs implied: no red / underdog red / favourite red ===")
for lab,m in (('no red',~M.red),('underdog red',M.dog_red),('favourite red',M.fav_red)):
    g=M[m]; print(f"{lab:14s} n {len(g):6d} fav won {g.fav_won.mean():.3f} implied {g.fav_p.mean():.3f}")
print("\nREADING: this is match-level only (no card minute). It says where cards are common and how much a red really shifts the result; the minute-level test (012) still needs API-Football events (key on server rejected) or the Betfair tape's own suspension signature.")
PYFILE
python3 fd_load.py
