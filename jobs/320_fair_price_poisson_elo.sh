#!/bin/bash
set -o pipefail
# 320: THE FAIR-PRICE MODEL — Poisson (attack/defence, time-decayed, walk-forward) and Elo, priced against the Betfair KICK-OFF
# print for every mapped game (29 leagues, 2024+2025). Walk-forward: each week's games are priced with a model fitted ONLY on games
# before that week (no look-ahead; the first 8 weeks of a league are skipped). Markets: Match Odds (home/draw/away) and Over/Under
# 2.5. Market probability = overround-normalised 1/LTP at the first print <= minute 2. Paper rule: back a runner at LTP-1 tick when
# model p >= market p + M points (M = 3/5/8/12); lay at LTP+1 tick when <= market p - M. 2% commission, £10 risk. Both seasons as
# halves, by league and market; calibration deciles; Poisson alone, Elo alone, 50/50 blend. Tables fair_price_games, fair_price_results.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,math,psycopg2,psycopg2.extras,pandas as pd,numpy as np
from collections import defaultdict
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(); cur.execute("SET statement_timeout='3000s'")
F=pd.read_sql("SELECT fixture_id, league_id, league, season, kickoff, home, away, hg, ag FROM af_fixtures WHERE status='FT' AND hg IS NOT NULL AND kickoff IS NOT NULL ORDER BY kickoff",con)
F['kickoff']=pd.to_datetime(F.kickoff,utc=True); print("fixtures:",len(F),"| leagues:",F.league_id.nunique(),flush=True)
M=pd.read_sql("SELECT substr(understat_id,3)::bigint fixture_id, event_id FROM af_price_map",con)
KO=pd.read_sql("""SELECT DISTINCT ON (event_id, mkt, sel) event_id, mkt, sel, ltp::float ltp FROM bf_hist_price
  WHERE mkt IN ('MO','OU25') AND minute BETWEEN 0 AND 2 AND ltp>1.01 AND event_id IN (SELECT event_id FROM af_price_map) ORDER BY event_id, mkt, sel, minute""",con)
KO=KO.merge(M,on='event_id'); px=KO.pivot_table(index='fixture_id',columns=['mkt','sel'],values='ltp'); px.columns=[f"{a}_{b}" for a,b in px.columns]
F=F.merge(px,left_on='fixture_id',right_index=True,how='inner'); print("games with kick-off prices:",len(F),flush=True)
# ---- walk-forward Poisson + Elo, refit per league per ISO week
HL=240.0  # half-life days for the Poisson weights
def fit_poisson(hist,now):
    teams=sorted(set(hist.home)|set(hist.away)); idx={t:i for i,t in enumerate(teams)}; n=len(teams)
    w=np.power(0.5,((now-hist.kickoff).dt.total_seconds()/86400.0)/HL).values
    hi=hist.home.map(idx).values; ai=hist.away.map(idx).values; hg=hist.hg.values.astype(float); ag=hist.ag.values.astype(float)
    att=np.ones(n); dfc=np.ones(n); hadv=1.25
    mu=(w*hg).sum()/w.sum(); mua=(w*ag).sum()/w.sum()
    for _ in range(25):
        # home goals ~ att[h]*def[a]*hadv*mu ; away goals ~ att[a]*def[h]*mua
        num=np.zeros(n); den=np.zeros(n)
        np.add.at(num,hi,w*hg); np.add.at(den,hi,w*dfc[ai]*hadv*mu); np.add.at(num,ai,w*ag); np.add.at(den,ai,w*dfc[hi]*mua)
        att=np.where(den>0,num/np.maximum(den,1e-9),1.0); att=att/np.average(att,weights=np.bincount(np.r_[hi,ai],minlength=n)+1e-9)
        num=np.zeros(n); den=np.zeros(n)
        np.add.at(num,ai,w*hg); np.add.at(den,ai,w*att[hi]*hadv*mu); np.add.at(num,hi,w*ag); np.add.at(den,hi,w*att[ai]*mua)
        dfc=np.where(den>0,num/np.maximum(den,1e-9),1.0); dfc=dfc/np.average(dfc,weights=np.bincount(np.r_[hi,ai],minlength=n)+1e-9)
        hadv=(w*hg).sum()/max(1e-9,(w*att[hi]*dfc[ai]*mu).sum())
    return idx,att,dfc,hadv,mu,mua
def probs(lh,la,maxg=10):
    ph=[math.exp(-lh)*lh**k/math.factorial(k) for k in range(maxg)]; pa=[math.exp(-la)*la**k/math.factorial(k) for k in range(maxg)]
    H=D=A=O=0.0
    for i in range(maxg):
        for j in range(maxg):
            p=ph[i]*pa[j]
            if i>j: H+=p
            elif i==j: D+=p
            else: A+=p
            if i+j>2: O+=p
    return H,D,A,O
out=[]
for lid,G in F.groupby('league_id',sort=False):
    G=G.sort_values('kickoff')
    hist_all=pd.read_sql("SELECT home, away, hg, ag, kickoff FROM af_fixtures WHERE league_id=%s AND status='FT' AND hg IS NOT NULL ORDER BY kickoff",con,params=(int(lid),)); hist_all['kickoff']=pd.to_datetime(hist_all.kickoff,utc=True)
    elo=defaultdict(lambda:1500.0); K=20.0; HFA=60.0
    # Elo walk-forward over ALL league games in order; Poisson refit per week
    G=G.set_index('fixture_id'); weeks=G.kickoff.dt.strftime('%G-%V'); fitted=None; fitted_week=None
    hist_iter=hist_all.reset_index(drop=True); hp=0
    for fid,g in G.iterrows():
        wk=weeks[fid]
        # advance Elo through all league games strictly before this kick-off
        while hp<len(hist_iter) and hist_iter.kickoff.iloc[hp]<g.kickoff:
            h=hist_iter.iloc[hp]; eh,ea=elo[h.home],elo[h.away]
            exph=1/(1+10**((ea-(eh+HFA))/400)); s=1.0 if h.hg>h.ag else 0.5 if h.hg==h.ag else 0.0
            gd=abs(h.hg-h.ag); mult=1.0 if gd<=1 else 1.5 if gd==2 else (11+gd)/8
            elo[h.home]+=K*mult*(s-exph); elo[h.away]-=K*mult*(s-exph); hp+=1
        if wk!=fitted_week:
            hist=hist_all[hist_all.kickoff<g.kickoff]
            fitted=fit_poisson(hist,g.kickoff) if len(hist)>=80 else None; fitted_week=wk
        if fitted is None: continue
        idx,att,dfc,hadv,mu,mua=fitted
        if g.home not in idx or g.away not in idx: continue
        lh=att[idx[g.home]]*dfc[idx[g.away]]*hadv*mu; la=att[idx[g.away]]*dfc[idx[g.home]]*mua
        pH,pD,pA,pO=probs(lh,la)
        d=(elo[g.home]+HFA)-elo[g.away]; eH=1/(1+10**(-d/400))
        # Elo -> 3-way via draw share from the Poisson draw rate at that strength gap
        eD=pD; eHome=max(0.02,eH-eD/2); eAway=max(0.02,1-eHome-eD)
        out.append((int(fid),int(lid),g.league,int(g.season),g.kickoff,g.home,g.away,int(g.hg),int(g.ag),pH,pD,pA,pO,eHome,eD,eAway,g.get('MO_HOME'),g.get('MO_DRAW'),g.get('MO_AWAY'),g.get('OU25_OVER'),g.get('OU25_UNDER')))
R=pd.DataFrame(out,columns=['fixture_id','league_id','league','season','kickoff','home','away','hg','ag','pH','pD','pA','pO','eH','eD','eA','mH','mD','mA','mO','mU'])
print("games priced by model with KO market:",len(R),flush=True)
cur.execute("DROP TABLE IF EXISTS fair_price_games"); cur.execute("CREATE TABLE fair_price_games (fixture_id BIGINT, league_id INT, league TEXT, season INT, kickoff TIMESTAMPTZ, home TEXT, away TEXT, hg INT, ag INT, p_h NUMERIC, p_d NUMERIC, p_a NUMERIC, p_o25 NUMERIC, elo_h NUMERIC, elo_d NUMERIC, elo_a NUMERIC, mkt_h NUMERIC, mkt_d NUMERIC, mkt_a NUMERIC, mkt_o NUMERIC, mkt_u NUMERIC)")
psycopg2.extras.execute_values(cur,"INSERT INTO fair_price_games VALUES %s",[tuple(None if (isinstance(v,float) and np.isnan(v)) else (float(v) if isinstance(v,(np.floating,)) else v) for v in row) for row in R.itertuples(index=False)],page_size=2000)
# ---- market probabilities (overround-normalised) and paper bets
def tick(p): return 0.01 if p<2 else 0.02 if p<3 else 0.05 if p<4 else 0.1 if p<6 else 0.2 if p<10 else 0.5 if p<20 else 1
mo=R.dropna(subset=['mH','mD','mA']).copy(); s=1/mo.mH+1/mo.mD+1/mo.mA; mo['qH']=(1/mo.mH)/s; mo['qD']=(1/mo.mD)/s; mo['qA']=(1/mo.mA)/s
ou=R.dropna(subset=['mO','mU']).copy(); s2=1/ou.mO+1/ou.mU; ou['qO']=(1/ou.mO)/s2
bets=[]
def add(df,model,sel,pcol,qcol,mcol,won):
    for Mg in (3,5,8,12):
        e=(df[pcol]-df[qcol])*100
        b=df[e>=Mg]; p=b[mcol]-b[mcol].map(tick); pnl=np.where(won(b),10*(p-1)*0.98,-10.0)
        for i,(fid,se,lg) in enumerate(zip(b.fixture_id,b.season,b.league)): bets.append((model,'BACK',sel,Mg,int(se),lg,float(pnl[i]),int(fid)))
        l=df[e<=-Mg]; p=l[mcol]+l[mcol].map(tick); st=10/(p-1); pnl=np.where(won(l),-10.0,st*0.98)
        for i,(fid,se,lg) in enumerate(zip(l.fixture_id,l.season,l.league)): bets.append((model,'LAY',sel,Mg,int(se),lg,float(pnl[i]),int(fid)))
for model,cols in (('poisson',('pH','pD','pA','pO')),('elo',('eH','eD','eA',None)),('blend',None)):
    if model=='blend':
        for c,(a,b) in zip(('bH','bD','bA'),(('pH','eH'),('pD','eD'),('pA','eA'))): mo[c]=(mo[a]+mo[b])/2
        cols=('bH','bD','bA',None)
    add(mo,model,'HOME',cols[0],'qH','mH',lambda b:b.hg>b.ag); add(mo,model,'DRAW',cols[1],'qD','mD',lambda b:b.hg==b.ag); add(mo,model,'AWAY',cols[2],'qA','mA',lambda b:b.hg<b.ag)
    if cols[3]: add(ou,model,'OVER25',cols[3],'qO','mO',lambda b:(b.hg+b.ag)>2)
B=pd.DataFrame(bets,columns=['model','side','sel','M','season','league','pnl','fixture_id'])
def t(x): return x.mean()/(x.std(ddof=1)/len(x)**0.5) if len(x)>1 and x.std(ddof=1)>0 else 0
def rep(dims):
    g=B.groupby(dims).agg(n=('pnl','size'),per10=('pnl','mean'),t=('pnl',t),h1=('pnl',lambda x:x[B.loc[x.index,'season']==2024].mean()),h2=('pnl',lambda x:x[B.loc[x.index,'season']==2025].mean()),n2=('pnl',lambda x:(B.loc[x.index,'season']==2025).sum())).round(3).reset_index()
    return g
cur.execute("DROP TABLE IF EXISTS fair_price_results; CREATE TABLE fair_price_results (level TEXT, model TEXT, side TEXT, sel TEXT, m INT, league TEXT, n INT, per10 NUMERIC, t NUMERIC, h1 NUMERIC, h2 NUMERIC, n2 INT)")
allr=[]
for dims in (['model','side','sel','M'],['model','side','M'],['model','side','sel','M','league']):
    g=rep(dims); g['level']='+'.join(dims)
    if 'sel' not in g: g['sel']=None
    if 'league' not in g: g['league']=None
    allr.append(g)
    for x in g.itertuples(): cur.execute("INSERT INTO fair_price_results VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)",(x.level,x.model,x.side,x.sel,int(x.M),x.league,int(x.n),float(x.per10),float(x.t),None if pd.isna(x.h1) else float(x.h1),None if pd.isna(x.h2) else float(x.h2),int(x.n2)))
A=pd.concat(allr,ignore_index=True)
print("\n== paper P&L per £10 by model x side x margin (h1 = 2024, h2 = 2025)"); print(A[A.level=='model+side+M'][['model','side','M','n','per10','t','h1','h2','n2']].to_string(index=False))
print("\n== by selection (M=5)"); print(A[(A.level=='model+side+sel+M')&(A.M==5)][['model','side','sel','n','per10','t','h1','h2']].to_string(index=False))
print("\n== calibration, Poisson home win: model p decile vs actual vs market")
mo['dec']=pd.qcut(mo.pH,10,duplicates='drop'); print(mo.groupby('dec',observed=True).agg(n=('hg','size'),model=('pH','mean'),market=('qH','mean'),actual=('hg',lambda x:(x>mo.loc[x.index,'ag']).mean())).round(3).to_string())
print("\n== log-loss (lower is better) on 2025 games: market vs poisson vs elo vs blend (3-way)")
def ll(P):
    y=np.where(mo.hg>mo.ag,0,np.where(mo.hg==mo.ag,1,2)); P=np.clip(P,1e-6,1); P=P/P.sum(axis=1,keepdims=True); return -np.log(P[np.arange(len(y)),y]).mean()
m25=mo[mo.season==2025]
for name,cols in (('market',['qH','qD','qA']),('poisson',['pH','pD','pA']),('elo',['eH','eD','eA']),('blend',['bH','bD','bA'])):
    y=np.where(m25.hg>m25.ag,0,np.where(m25.hg==m25.ag,1,2)); P=np.clip(m25[cols].values,1e-6,1); P=P/P.sum(axis=1,keepdims=True); print(f"  {name:8s} {(-np.log(P[np.arange(len(y)),y])).mean():.4f}  (n {len(y)})")
S=A[(A.n>=300)&(A.t>=3.5)&(A.h1>0)&(A.h2>0)&(A.per10>=0.15)].sort_values('t',ascending=False)
print(f"\n== SURVIVORS: {len(S)}"); print(S.head(30).to_string(index=False) if len(S) else "none")
PY
