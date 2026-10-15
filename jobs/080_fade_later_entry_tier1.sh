#!/bin/bash
# 080: THE FOUR-FIGURE QUESTION. Does the post-goal fade still pay when entered LATER, where the size is? Entry = lay the scorer
# (MO runner whose LTP fell 10%+ on reopen) at the BEST LAY price recorded at +60 / +120 / +300s (real ladder, liq_goal_depth);
# exit = back at the best back from liq_sample (1/min) nearest +10 min after entry, or the market's last sample if the game ends.
# Same for Over 2.5. By tier (top5+UCL / other Europe / rest), minute band, price band. Costs: real spread (we use the quoted side)
# + 2% commission. Also prints the median size within 3 ticks at each entry so P&L x size = £ per goal.
cd /root/pe-scan && python3 - <<'PY'
import sys, math, psycopg2, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
COMM=0.02
con=psycopg2.connect(DB,sslmode='require')
G=pd.read_sql("SELECT market_id, event_name, competition, mkt, sel, goal_ts, offset_s, ts, pre_ltp, ltp, back_px, lay_px, lay_sz, lay3_sz, minute FROM liq_goal_depth WHERE offset_s IN (60,120,300) AND lay_px IS NOT NULL",con)
S=pd.read_sql("SELECT ts, market_id, sel, back_px, lay_px FROM liq_sample WHERE back_px IS NOT NULL",con).sort_values('ts')
for c in ('pre_ltp','ltp','back_px','lay_px','lay_sz','lay3_sz'): G[c]=pd.to_numeric(G[c],errors='coerce')
S['back_px']=pd.to_numeric(S.back_px,errors='coerce')
G['moved']=G.ltp/G.pre_ltp-1
E=G[((G.mkt=='MO')&(G.moved<-0.10))|((G.mkt=='OU25')&(G.sel=='OVER'))].copy()
TOP5={'English Premier League','Spanish La Liga','Italian Serie A','German Bundesliga','French Ligue 1','UEFA Champions League'}
EUR={'English Championship','Dutch Eredivisie','Portuguese Primeira Liga','Belgian Pro League','Turkish Super League','Scottish Premiership','Spanish Segunda Division','Italian Serie B','German Bundesliga 2','French Ligue 2','UEFA Europa League'}
E['tier']=E.competition.map(lambda c:'1 top5+UCL' if c in TOP5 else '2 other Europe' if c in EUR else '3 rest')
SK={k:g for k,g in S.groupby(['market_id','sel'])}
def exit_px(mid,sel,when):
    g=SK.get((mid,sel))
    if g is None: return None
    i=g.ts.searchsorted(when)
    cands=[j for j in (i-1,i) if 0<=j<len(g)]
    if not cands: return None
    j=min(cands,key=lambda j:abs((g.ts.iloc[j]-when).total_seconds()))
    if abs((g.ts.iloc[j]-when).total_seconds())>180: return None
    return float(g.back_px.iloc[j])
E['exit']=[exit_px(m,s,t+pd.Timedelta(minutes=10)) for m,s,t in zip(E.market_id,E.sel,E.ts)]
E=E[E.exit.notna()&(E.lay_px>1.01)].copy()
E['pnl']=1-(E.lay_px/E.exit); E['pnl']=np.where(E.pnl>0,E.pnl*(1-COMM),E.pnl)   # per £1 stake laid
E['pnl_liab']=E.pnl/(E.lay_px-1)
E['pband']=pd.cut(E.lay_px,[1,1.3,1.6,2,3,5,100],labels=['<1.3','1.3-1.6','1.6-2','2-3','3-5','5+'])
E['mb']=pd.cut(E.minute.fillna(0),[-1,30,60,80,200],labels=['0-30','31-60','61-80','81+'])
pd.set_option('display.width',240); pd.set_option('display.max_rows',300)
def tstat(x): x=x.dropna(); return round(float(x.mean()/(x.std(ddof=1)/math.sqrt(len(x)))),1) if len(x)>2 and x.std(ddof=1)>0 else 0.0
print("entries priced with a +10 min exit:",len(E))
for mkt in ('MO','OU25'):
    X=E[E.mkt==mkt]
    print(f"\n=== {mkt}: lay at best lay at +offset, back out at +10 min — P&L per £100 STAKE, by tier x offset ===")
    t=X.groupby(['tier','offset_s']).agg(n=('pnl','size'),per100=('pnl',lambda x:round(100*x.mean(),1)),t=('pnl',tstat),size3_med=('lay3_sz','median'),size3_p75=('lay3_sz',lambda x:x.quantile(.75)))
    t['£_per_goal_at_med_size']=(t.per100/100*t.size3_med).round(1); print(t.to_string())
    print(f"\n--- {mkt} tier 1 + 2 only, by price band x offset ---")
    t=X[X.tier!='3 rest'].groupby(['pband','offset_s'],observed=True).agg(n=('pnl','size'),per100=('pnl',lambda x:round(100*x.mean(),1)),t=('pnl',tstat)); print(t.unstack('offset_s').to_string())
    print(f"\n--- {mkt} tier 1 + 2, by minute band x offset ---")
    t=X[X.tier!='3 rest'].groupby(['mb','offset_s'],observed=True).agg(n=('pnl','size'),per100=('pnl',lambda x:round(100*x.mean(),1)),t=('pnl',tstat)); print(t.unstack('offset_s').to_string())
print("\nREADING: one week of goals, no train/test split possible yet — this is a direction, not a verdict. £_per_goal = edge x size actually there within 3 ticks.")
PY
