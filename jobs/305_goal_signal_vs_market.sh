#!/bin/bash
set -o pipefail
# 305: GOAL SIGNAL vs THE MARKET — the half of the job never done. goal_live_predictions holds, per minute, the model's
# probability of further goals AND the Betfair Under 2.5 price at that moment. Where the score total is exactly 2, the market's
# Under 2.5 price IS the market's probability of "no more goals", directly comparable with the model's 1 - p_goal_rest_of_match.
# Paper rule: back Under when model says no-more-goals is >= M points higher than the market implies; back Over (lay Under) when
# it is >= M points lower. One prediction per fixture per 5-minute bucket (de-correlated), price one tick adverse, 2% commission,
# £10 risk. Split by margin M (3/5/8/12 pts), by minute band, by data era (delayed key before 27 Oct / live key after), by league.
# Survivors printed: n>=200, t>=3.5, both eras >0.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor(); cur.execute("SET statement_timeout='2400s'")
D=pd.read_sql("""
WITH p AS (
  SELECT fixture_id, captured_at, minute, score_home+score_away tot, p_goal_rest_of_match::float p_rest, under25_price::float u25,
         settled, next_goal_minute, goal_within_15,
         row_number() OVER (PARTITION BY fixture_id, minute/5 ORDER BY captured_at) rn
  FROM goal_live_predictions
  WHERE settled AND p_goal_rest_of_match IS NOT NULL AND under25_price IS NOT NULL AND under25_price>1.01 AND under25_price<20
    AND score_home+score_away=2 AND minute BETWEEN 1 AND 85)
SELECT p.fixture_id, p.captured_at, p.minute, p.p_rest, p.u25, p.next_goal_minute, p.goal_within_15, ft.ft_tot, ft.league
FROM p JOIN (SELECT DISTINCT ON (fixture_id) fixture_id, score_home+score_away ft_tot, league_name league FROM goal_timeline WHERE minute>=80 ORDER BY fixture_id, captured_at DESC) ft ON ft.fixture_id=p.fixture_id
WHERE p.rn=1""",con)
print("predictions at total=2:",len(D),"| fixtures:",D.fixture_id.nunique(),"| from",D.captured_at.min(),"to",D.captured_at.max(),flush=True)
D=D[D.ft_tot.notna()].copy()
D['no_more']=(D.ft_tot<=2)                      # Under 2.5 wins
D['model_p']=1-D.p_rest; D['mkt_p']=1/D.u25
D['edge']=(D.model_p-D.mkt_p)*100
D['era']=np.where(pd.to_datetime(D.captured_at)>=pd.Timestamp('2026-10-27',tz='UTC'),'live-key','delayed-key')
def tick(p): return 0.01 if p<2 else 0.02 if p<3 else 0.05 if p<4 else 0.1 if p<6 else 0.2 if p<10 else 0.5
rows=[]
for M in (3,5,8,12):
    b=D[D.edge>=M].copy(); b['side']='BACK_UNDER'; p=b.u25-b.u25.map(tick)
    b['pnl']=np.where(b.no_more,(10*(p-1))*0.98,-10.0); b['M']=M; rows.append(b)
    l=D[D.edge<=-M].copy(); l['side']='LAY_UNDER'; p=l.u25+l.u25.map(tick); s=10/(p-1)
    l['pnl']=np.where(l.no_more,-10.0,s*0.98); l['M']=M; rows.append(l)
R=pd.concat(rows,ignore_index=True)
R['mband']=pd.cut(R.minute,[0,30,45,60,75,85],labels=['1-30','31-45','46-60','61-75','76-85'])
def t(x): return x.mean()/(x.std(ddof=1)/len(x)**0.5) if len(x)>1 and x.std(ddof=1)>0 else 0
def rep(dims):
    g=R.groupby(dims,observed=True).agg(n=('pnl','size'),fixtures=('fixture_id','nunique'),per10=('pnl','mean'),t=('pnl',t),
        h1=('pnl',lambda x:x[R.loc[x.index,'era']=='delayed-key'].mean()),h2=('pnl',lambda x:x[R.loc[x.index,'era']=='live-key'].mean()),
        n2=('pnl',lambda x:(R.loc[x.index,'era']=='live-key').sum())).round(3)
    return g
cur.execute("DROP TABLE IF EXISTS gs_vs_market; CREATE TABLE gs_vs_market (level TEXT, side TEXT, m INT, mband TEXT, league TEXT, n INT, fixtures INT, per10 NUMERIC, t NUMERIC, h1 NUMERIC, h2 NUMERIC, n_live INT)"); con.commit()
out=[]
for dims in (['side','M'],['side','M','mband'],['side','M','league']):
    g=rep(dims).reset_index(); g['level']='+'.join(dims)
    for c in ('mband','league'):
        if c not in g: g[c]=None
    out.append(g)
    for x in g.itertuples(): cur.execute("INSERT INTO gs_vs_market VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)",(x.level,x.side,int(x.M),None if x.mband is None else str(x.mband),x.league,int(x.n),int(x.fixtures),float(x.per10),float(x.t),None if pd.isna(x.h1) else float(x.h1),None if pd.isna(x.h2) else float(x.h2),int(x.n2)))
con.commit()
A=pd.concat(out,ignore_index=True)
print("\n== model vs market, all minutes (per £10; h1 = delayed-key era, h2 = live-key era)")
print(A[A.level=='side+M'][['side','M','n','fixtures','per10','t','h1','h2','n2']].to_string(index=False))
print("\n== calibration: does the model's edge predict the outcome at all?")
D['eb']=pd.cut(D.edge,[-100,-12,-8,-5,-3,3,5,8,12,100])
print(D.groupby('eb',observed=True).agg(n=('no_more','size'),model_p=('model_p','mean'),market_p=('mkt_p','mean'),actual=('no_more','mean')).round(3).to_string())
S=A[(A.n>=200)&(A.t>=3.5)&(A.h1>0)&(A.h2>0)&(A.per10>=0.15)].sort_values('t',ascending=False)
print(f"\n== SURVIVORS: {len(S)}"); print(S[['level','side','M','mband','league','n','per10','t','h1','h2','n2']].head(30).to_string(index=False) if len(S) else "none")
PY
