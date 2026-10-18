#!/bin/bash
# 102: TENNIS LIVE vs PAPER — same strategy, same fortnight: paper 813 trades 33% green +4.8%/liability, live 68 trades 24% green
# -£11.66. Join every live trade to its paper row (market_id + selection_id, else event+player) and classify: paper GREEN/live STOP
# (= stop mechanics / slippage), both STOP (= selection), live GREEN/paper STOP. Plus entry and exit price gaps and the stop trigger.
python3 - <<'PY'
import sys, psycopg2, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require'); pd.set_option('display.width',240); pd.set_option('display.max_rows',200)
L=pd.read_sql("SELECT id, opened_at, market_id, selection_id, event_name, player, competition, lay_price::float lay_price, exit_price::float exit_price, green_target::float gt, stop_level::float sl, outcome, pnl::float pnl FROM tennis_positions WHERE closed_at IS NOT NULL",con)
P=pd.read_sql("SELECT play_date, market_id, selection_id, event_name, player, entry_at::float entry_at, lay_at::float lay_at, green_target::float pgt, stop_level::float psl, outcome p_outcome, exit_price::float p_exit, mins_held, pnl_per_1_liability::float p_pnl FROM tennis_lay_paper WHERE outcome IN ('GREEN','STOP')",con)
J=L.merge(P,on=['market_id','selection_id'],how='left',suffixes=('','_p'))
J['match']=np.where(J.p_outcome.notna(),'by id','none')
miss=J[J.p_outcome.isna()].drop(columns=[c for c in J.columns if c.endswith('_p') or c.startswith('p_') or c in ('entry_at','lay_at','pgt','psl','play_date','mins_held')])
if len(miss):
    m2=miss.merge(P,on=['event_name','player'],how='left'); m2['match']=np.where(m2.p_outcome.notna(),'by name','none'); J=pd.concat([J[J.p_outcome.notna()],m2])
print("live",len(L),"matched to paper:",(J.match!='none').sum(),"| unmatched",(J.match=='none').sum())
J['cls']=J.outcome.fillna('?')+' live / '+J.p_outcome.fillna('no paper')+' paper'
print("\n== classification ==\n",J.groupby('cls').agg(n=('id','size'),live_pnl=('pnl','sum'),paper_pnl_per_liab=('p_pnl','mean')).round(2).to_string())
J['entry_gap_pct']=(J.lay_price/J.lay_at-1)*100; J['stop_gap']=J.sl-J.psl
print("\n== entry price live vs paper: median gap %",round(J.entry_gap_pct.median(),2),"| mean",round(J.entry_gap_pct.mean(),2))
print("== stop level live vs paper (ticks of price):",J.stop_gap.describe().round(3).to_dict())
print("\n== the divergent trades (paper GREEN, live STOP) ==")
d=J[(J.outcome=='STOP')&(J.p_outcome=='GREEN')][['event_name','player','lay_price','lay_at','sl','psl','exit_price','p_exit','mins_held','pnl','p_pnl']]
print(d.round(3).to_string(index=False))
print("\n== paper candidates the live bot did NOT take (same days): outcome mix ==")
days=pd.to_datetime(L.opened_at).dt.date.unique()
Pn=P[pd.to_datetime(P.play_date).dt.date.isin(days)&~P.market_id.isin(L.market_id)]
print(Pn.groupby('p_outcome').agg(n=('p_pnl','size'),pnl=('p_pnl','mean')).round(3).to_string(), "| live-taken paper rows:",J.p_outcome.value_counts().to_dict())
print("\nREADING: if most live STOPs are paper GREENs -> stop mechanics (widen stop to 20% or trigger on last-traded, not touch). If paper also STOPped -> selection (the £100k/main-tour subset is the bad slice; use the paper's filters instead). If untaken candidates green more -> max_open/max_day is throwing away the good ones.")
PY
