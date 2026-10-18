#!/bin/bash
# 101: T2 LIVE BREAKDOWN — 68 closed trades, 16 wins, -£11.66 vs a backtest expecting ~35-40% strike. Cut the live trades by
# entry (lay/back) price band, drift from pre-match, ATP/WTA (competition name), tournament level, and fill slippage vs the
# tape, so the next step is a filter or "variance, continue to 100", not a guess.
python3 - <<'PY'
import sys, math, psycopg2, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require'); pd.set_option('display.width',220)
T=pd.read_sql("SELECT * FROM tennis_positions WHERE closed_at IS NOT NULL ORDER BY opened_at",con)
print("closed",len(T),"wins",(T.pnl>0).sum(),"pnl",round(T.pnl.sum(),2)); print(T.columns.tolist())
for c in ('lay_price','stake','exit_price','pnl','green_target','stop_level'): T[c]=pd.to_numeric(T[c],errors='coerce')
T['win']=T.pnl>0; T['tour']=np.where(T.competition.str.contains('WTA|Women|W15|W35|W50|W75|W100',case=False,na=False),'WTA',np.where(T.competition.str.contains('ATP|Challenger|M15|M25',case=False,na=False),'ATP','other'))
T['level']=np.where(T.competition.str.contains('Challenger|ITF|M15|M25|W15|W35|W50|W75|W100',case=False,na=False),'lower','main')
T['pband']=pd.cut(T.lay_price,[1,1.5,2,2.5,3,4,6,100])
def rep(by):
    g=T.groupby(by,observed=True).agg(n=('pnl','size'),wins=('win','sum'),pnl=('pnl','sum'),avg_entry=('lay_price','mean')); g['sr']=(g.wins/g.n*100).round(0); print(f"\n== by {by} ==\n",g.round(2).to_string())
for by in ('tour','level','pband','outcome'): rep(by)
print("\n== outcome x exit reason sample ==\n",T[['opened_at','event_name','competition','lay_price','exit_price','outcome','pnl']].tail(20).to_string(index=False))
# slippage: what did the tape (bf_tennis_log) show at the same moment for the same selection?
try:
    L=pd.read_sql("SELECT market_id, selection_id, captured_at, back_price, lay_price FROM bf_tennis_log WHERE captured_at>=%s",con,params=(T.opened_at.min(),))
    L['captured_at']=pd.to_datetime(L.captured_at,utc=True); T['opened_at']=pd.to_datetime(T.opened_at,utc=True)
    sl=[]
    for r in T.itertuples():
        g=L[(L.market_id==r.market_id)&(L.selection_id==r.selection_id)]
        if g.empty: continue
        i=(g.captured_at-r.opened_at).abs().idxmin(); sl.append((r.lay_price, float(g.loc[i,'lay_price'] or np.nan), float(g.loc[i,'back_price'] or np.nan)))
    S=pd.DataFrame(sl,columns=['filled','tape_lay','tape_back']); print("\n== fill vs tape (n",len(S),") median filled",S.filled.median(),"tape lay",S.tape_lay.median(),"tape back",S.tape_back.median())
except Exception as e: print("slippage check skipped",repr(e)[:100])
print("\nREADING: a band/tour with n>=15 and SR under 20% is a filter candidate; if every cut is 20-30% with small n, verdict is variance -> continue to 100.")
PY
