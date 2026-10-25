#!/bin/bash
# 203: LIVE-LADDER REPLAY of the two other flagged price-only cells that need no exit (settle at FT), same method as 192:
#   (a) one-goal lead at 75' (odd goal count, draw >= 5.0, leader <= 1.5): LAY the draw at the real lay price, settle at FT
#   (b) same state: BACK the leader at the real back price, settle at FT
# Markets tracked from kick-off to 88'+ in liq_sample, goals from liq_goal_depth, result from final prices (<= 1.15). 2% commission.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys, psycopg2, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
pd.set_option('display.width',220); COMM=0.02
con=psycopg2.connect(DB,sslmode='require')
mk=pd.read_sql("SELECT market_id FROM liq_sample WHERE mkt='MO' AND minute<=5 GROUP BY market_id HAVING max(minute)>=88",con); mids=list(mk.market_id); print("markets:",len(mids))
S=pd.read_sql("SELECT market_id, event_name, competition, ts, minute, sel, ltp::float ltp, back_px::float bp, lay_px::float lp, back_sz::float bsz, lay_sz::float lsz FROM liq_sample WHERE mkt='MO' AND market_id = ANY(%s) ORDER BY market_id, ts",con,params=(mids,))
G=pd.read_sql("SELECT market_id, min(goal_ts) goal_ts, minute FROM liq_goal_depth WHERE mkt='MO' AND market_id = ANY(%s) GROUP BY market_id, minute",con,params=(mids,))
goals={m:sorted(g.goal_ts.tolist()) for m,g in G.groupby('market_id')}
rows=[]
for mid,g in S.groupby('market_id',sort=False):
    d=g[g.sel=='DRAW']; h=g[g.sel=='HOME']; a=g[g.sel=='AWAY']
    if d.empty or h.empty or a.empty: continue
    last=g[g.ts==g.ts.max()]; fin={r.sel:r.ltp for r in last.itertuples() if pd.notna(r.ltp)}
    if not fin: continue
    wsel=min(fin,key=fin.get); winner=wsel if fin[wsel]<=1.15 else None
    if winner is None: continue
    e=d[(d.minute>=75)&(d.minute<=77)&d.lp.notna()]
    if e.empty: continue
    r0=e.iloc[0]; ng=sum(1 for t in goals.get(mid,[]) if t<r0.ts)
    if ng%2==0: continue                                   # need an odd goal count (one-goal lead)
    hp=h[(h.ts<=r0.ts)&h.bp.notna()]; ap=a[(a.ts<=r0.ts)&a.bp.notna()]
    if hp.empty or ap.empty: continue
    hb,ab=hp.iloc[-1].bp,ap.iloc[-1].bp; lead='HOME' if hb<ab else 'AWAY'; lb=min(hb,ab)
    if not (r0.lp>=5.0 and lb<=1.5): continue             # state check: market agrees it is a one-goal lead
    if (r0.lsz or 0)<10: continue
    # (a) lay draw to FT
    pa=(-10*(r0.lp-1)) if winner=='DRAW' else 10*(1-COMM)
    # (b) back leader to FT
    pb=(10*(lb-1)*(1-COMM)) if winner==lead else -10.0
    rows.append(dict(event=g.event_name.iloc[0],comp=g.competition.iloc[0],lay_draw=r0.lp,leader=lb,winner=winner,lead=lead,p_laydraw=round(pa,2),p_backlead=round(pb,2)))
R=pd.DataFrame(rows); print("\nLIVE LADDER — one-goal lead at 75', draw >= 5.0, leader <= 1.5:",len(R),"trades")
if len(R):
    for c in ('p_laydraw','p_backlead'):
        x=R[c]; print(f"{c:12s} mean per £10 {x.mean():+.2f} | win {(x>0).mean():.0%} | total £{x.sum():+.1f} | t {x.mean()/(x.std(ddof=1)/np.sqrt(len(x))) if len(x)>2 else 0:.2f}")
    print("\nby draw band:\n",R.assign(band=pd.cut(R.lay_draw,[5,7,10,15,100])).groupby('band',observed=True)[['p_laydraw','p_backlead']].agg(['size','mean']).round(2).to_string())
    print("\noutcomes:",R.winner.eq('DRAW').sum(),"draws of",len(R),"| backtest said draw lay +5.49/£10, 94% win, n 879")
    print(R.sample(min(8,len(R)),random_state=2).to_string(index=False))
PY
