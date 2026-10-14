#!/bin/bash
# 060: PETER'S FAN-BIAS TEST (14 Oct prompt). "Emotional money backs big clubs regardless of price." On fd_matches (36,979 matches,
# 5 seasons, opening B365 and Pinnacle CLOSING odds): (1) does the big-club price SHORTEN from open to close more than other teams
# (systematic fan drift)? (2) lay the big club at closing price to FT: P&L per £100 liability after 2% comm, split home/away,
# derby/top-clash vs rest; seasons 21/22-23/24 in-sample, 24/25-25/26 out-of-sample. Big clubs: PL big six + Celtic/Rangers +
# Real/Barca/Atletico + Bayern/Dortmund + Juve/Inter/Milan + PSG + Benfica/Porto/Sporting + Ajax/PSV + Galatasaray/Fenerbahce.
cd /root/pe-scan && cat > fan_bias.py <<'PYFILE'
import sys, math, psycopg2, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
COMM=0.02
con=psycopg2.connect(DB,sslmode='require')
M=pd.read_sql("SELECT div,season,match_date,home_team,away_team,fthg,ftag,b365h,b365d,b365a,psch,pscd,psca, raw->>'PSH' psh, raw->>'PSA' psa FROM fd_matches WHERE psch IS NOT NULL AND b365h IS NOT NULL",con)
for c in ('psh','psa'): M[c]=pd.to_numeric(M[c],errors='coerce')
BIG={'Man City','Man United','Liverpool','Arsenal','Chelsea','Tottenham','Celtic','Rangers','Real Madrid','Barcelona','Ath Madrid','Bayern Munich','Dortmund','Juventus','Inter','Milan','Paris SG','Benfica','Porto','Sp Lisbon','Ajax','PSV Eindhoven','Galatasaray','Fenerbahce'}
print("matches",len(M),"big-club names present:",sorted(BIG & set(M.home_team)|BIG & set(M.away_team)))
rows=[]
for r in M.itertuples():
    for side in ('H','A'):
        team=r.home_team if side=='H' else r.away_team
        if team not in BIG: continue
        opp=r.away_team if side=='H' else r.home_team
        op=r.b365h if side=='H' else r.b365a; cl=r.psch if side=='H' else r.psca; pin_open=r.psh if side=='H' else r.psa
        won=(r.fthg>r.ftag) if side=='H' else (r.ftag>r.fthg)
        if not cl or cl<=1: continue
        lay=-1.0 if won else (1/(cl-1))*(1-COMM)   # lay to 1pt liability at closing price
        back=((cl-1)*(1-COMM)) if won else -1.0
        rows.append((r.season,r.div,team,opp,side,op,pin_open,cl,won,lay,back,opp in BIG))
D=pd.DataFrame(rows,columns=['season','div','team','opp','side','b365_open','pin_open','close','won','lay','back','clash'])
D['split']=np.where(D.season.isin(['2122','2223','2324']),'in 21-24','out 24-26')
D['drift']=D.close/D.pin_open-1
pd.set_option('display.width',240)
print("\n=== 1. Opening->closing drift on the big club (Pinnacle open -> Pinnacle close, negative = shortened) ===")
print(D.groupby(['split','side']).drift.agg(['size','median','mean']).round(4).to_string())
# control: every non-big team's drift
C=[]
for r in M.itertuples():
    for side,t,o,c in (('H',r.home_team,r.psh,r.psch),('A',r.away_team,r.psa,r.psca)):
        if t in BIG or not o or not c: continue
        C.append((side,c/o-1))
C=pd.DataFrame(C,columns=['side','drift']); print("control (all other teams) median drift:",C.groupby('side').drift.median().round(4).to_dict())
def tstat(x): x=x.dropna(); return round(float(x.mean()/(x.std(ddof=1)/math.sqrt(len(x)))),1) if len(x)>2 and x.std(ddof=1)>0 else 0.0
def rep(g,title):
    print(f"\n=== {title} ===")
    t=g.groupby(['split']).agg(n=('lay','size'),win_rate=('won','mean'),implied=('close',lambda x:(1/x).mean()),lay_per100=('lay',lambda x:100*x.mean()),back_per100=('back',lambda x:100*x.mean()))
    t['t_lay']=g.groupby('split').lay.apply(tstat); print(t.round(3).to_string())
rep(D,'2. LAY big club at closing price, all')
rep(D[D.side=='H'],'3. home only'); rep(D[D.side=='A'],'4. away only')
rep(D[D.clash],'5. big club v big club'); rep(D[~D.clash],'6. big club v the rest')
D['pband']=pd.cut(D.close,[1,1.3,1.6,2,3,5,100],labels=['<1.3','1.3-1.6','1.6-2','2-3','3-5','5+'])
print("\n=== 7. by closing price band x split (lay per £100 liability, t) ===")
t=D.groupby(['pband','split'],observed=True).agg(n=('lay','size'),lay_per100=('lay',lambda x:round(100*x.mean(),1)),t=('lay',tstat)); print(t.unstack('split').to_string())
print("\n=== 8. by team (out-of-sample only, n>=30) ==="); t=D[D.split=='out 24-26'].groupby('team').agg(n=('lay','size'),win=('won','mean'),lay_per100=('lay',lambda x:round(100*x.mean(),1))); print(t[t.n>=30].sort_values('lay_per100',ascending=False).round(3).to_string())
print("\nVERDICT RULE: fan bias exists if (1) big clubs shorten open->close more than the control AND (2) laying them at close is positive in BOTH splits with t>=2. If (1) holds but (2) fails, the bias is priced in by close -> the trade is to lay EARLY and back at close (needs our own 7am tape).")
PYFILE
python3 fan_bias.py
