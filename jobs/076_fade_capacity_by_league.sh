#!/bin/bash
# 076: HOW BIG CAN THE POST-GOAL FADE GO IN THE MARKETS THAT MATTER? liq_goal_depth holds the full ladder at +0/30/60/120/300s for
# ~3,900 goals since 12 Oct, Match Odds + O/U 2.5. Per competition tier (top-5 leagues / other European / rest) and offset: median and
# 75th-pct size at best price and within 3 ticks on the lay side of the scorer and the lay side of Over 2.5, plus total matched in
# the 5 minutes after the goal. This is the stake the fade can carry per goal in the big games, by market.
cd /root/pe-scan && python3 - <<'PY'
import sys, psycopg2, pandas as pd
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require')
D=pd.read_sql("SELECT competition, mkt, sel, offset_s, pre_ltp, ltp, back_sz, lay_sz, back3_sz, lay3_sz, total_matched, matched_since_goal, minute FROM liq_goal_depth",con)
for c in ('pre_ltp','ltp','back_sz','lay_sz','back3_sz','lay3_sz','total_matched','matched_since_goal'): D[c]=pd.to_numeric(D[c],errors='coerce')
TOP5={'English Premier League','Spanish La Liga','Italian Serie A','German Bundesliga','French Ligue 1','UEFA Champions League'}
EUR={'English Championship','Dutch Eredivisie','Portuguese Primeira Liga','Belgian Pro League','Turkish Super League','Scottish Premiership','Spanish Segunda Division','Italian Serie B','German Bundesliga 2','French Ligue 2','UEFA Europa League'}
D['tier']=D.competition.map(lambda c:'1 top5+UCL' if c in TOP5 else '2 other Europe' if c in EUR else '3 rest')
# the scorer = the MO runner whose price FELL on reopen; Over = OU25 OVER
D['moved']=D.ltp/D.pre_ltp-1
S=D[((D.mkt=='MO')&(D.moved<-0.10))|((D.mkt=='OU25')&(D.sel=='OVER'))].copy()
S['price_band']=pd.cut(S.ltp,[1,1.3,1.6,2,3,5,100],labels=['<1.3','1.3-1.6','1.6-2','2-3','3-5','5+'])
pd.set_option('display.width',240); pd.set_option('display.max_rows',300)
print("goals in sample:",D.groupby('tier').apply(lambda g: g[['competition','minute']].drop_duplicates().shape[0]).to_dict())
for mkt in ('MO','OU25'):
    X=S[S.mkt==mkt]
    print(f"\n=== {mkt}: LAY-side size available (£) by tier x offset — median / 75th pct, at best price and within 3 ticks ===")
    g=X.groupby(['tier','offset_s']).agg(n=('lay_sz','size'),best_med=('lay_sz','median'),best_p75=('lay_sz',lambda x:x.quantile(.75)),ticks3_med=('lay3_sz','median'),ticks3_p75=('lay3_sz',lambda x:x.quantile(.75)),matched_since_med=('matched_since_goal','median')).round(0)
    print(g.to_string())
    print(f"\n--- {mkt}: tier 1 only, by price band at +60s ---")
    print(X[(X.tier=='1 top5+UCL')&(X.offset_s==60)].groupby('price_band',observed=True).agg(n=('lay_sz','size'),best_med=('lay_sz','median'),ticks3_med=('lay3_sz','median'),ticks3_p75=('lay3_sz',lambda x:x.quantile(.75))).round(0).to_string())
print("\n=== Total matched on the market at the goal, by tier (median £) ===")
print(D[D.offset_s==0].groupby(['tier','mkt']).total_matched.median().round(0).unstack('mkt').to_string())
print("\nREADING: stake per goal the fade can take without moving the price = ticks3 size at the chosen offset. Multiply by goals per weekend in that tier for weekly capacity.")
PY
