#!/bin/bash
# 230: TENNIS T2 (first-set comeback) ON OUR OWN IN-PLAY TAPE — the March playbook's primary tennis rule (vendor-validated +26.6% ROI ATP,
# +23.7% WTA) has never been run on our data. ip_tape holds tennis MATCH_ODDS (and SET_WINNER where recorded) ~1/min since 13 Oct.
# Rule: pre-match favourite at 1.30-2.00 (first in-play price); detect "lost set 1" as the favourite's best back drifting to >= 1.6x its
# pre-match price within the first 60 minutes with the match still open (the vendor's trigger is the set score; price drift is our
# proxy until the set-score feed exists); back at that drifted price; settle at the close (winner = price <= 1.05 at the end), with a
# hedged variant: lay back at 20 min later. 2% spread + 2% comm. Output by drift band and by hedged/settle, both halves of the sample.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys, psycopg2, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
pd.set_option('display.width',220); con=psycopg2.connect(DB,sslmode='require'); SP=0.02; CM=0.02
mk=pd.read_sql("SELECT market_id FROM ip_tape WHERE sport ILIKE 'tennis' AND market_type='MATCH_ODDS' GROUP BY market_id HAVING min(secs_since_start)<=600 AND max(secs_since_start)>=3600 AND count(*)>=60",con)
mids=list(mk.market_id); print("tennis matches tracked from near the start:",len(mids))
T=pd.read_sql("SELECT market_id, event_name, competition, ts, secs_since_start s, status, sel_id, sel_name, back_px::float bp, lay_px::float lp, ltp::float ltp FROM ip_tape WHERE sport ILIKE 'tennis' AND market_type='MATCH_ODDS' AND market_id = ANY(%s) AND back_px IS NOT NULL ORDER BY market_id, ts",con,params=(mids,))
rows=[]
for mid,g in T.groupby('market_id',sort=False):
    sels=g.sel_id.unique()
    if len(sels)!=2: continue
    first=g[g.s<=600]
    if first.empty: continue
    sp={s:first[first.sel_id==s].bp.iloc[0] for s in sels if not first[first.sel_id==s].empty}
    if len(sp)<2: continue
    fav=min(sp,key=sp.get); p0=sp[fav]
    if not (1.30<=p0<=2.00): continue
    f=g[(g.sel_id==fav)].sort_values('ts'); last=g[g.ts==g.ts.max()]
    fin={r.sel_id:r.bp for r in last.itertuples()}; w=min(fin,key=fin.get); winner=w if fin[w]<=1.05 else None
    if winner is None: continue
    e=f[(f.s<=3600)&(f.bp>=1.6*p0)&(f.bp<=15)]
    if e.empty: continue
    r0=e.iloc[0]; px=r0.bp*(1-SP); won=(winner==fav)
    p_settle=(10*(px-1)*(1-CM)) if won else -10.0
    x=f[f.ts>=r0.ts+pd.Timedelta(minutes=20)]
    if x.empty: continue
    hx=x.iloc[0].lp*(1+SP); p_hedge=10*(px/hx-1); p_hedge=p_hedge*(1-CM) if p_hedge>0 else p_hedge
    rows.append(dict(event=g.event_name.iloc[0],comp=g.competition.iloc[0],ts=r0.ts,p0=p0,entry=r0.bp,drift=round(r0.bp/p0,2),mins=int(r0.s//60),won=won,p_settle=round(p_settle,2),p_hedge=round(p_hedge,2)))
R=pd.DataFrame(rows); print("T2 qualifying entries:",len(R))
if len(R):
    R['half']=np.where(R.ts<R.ts.median(),'H1','H2'); R['band']=pd.cut(R.drift,[1.6,2.0,2.5,3.5,10])
    for c in ('p_settle','p_hedge'):
        x=R[c]; print(f"{c}: mean per £10 {x.mean():+.2f} | win {(x>0).mean():.0%} | t {x.mean()/(x.std(ddof=1)/np.sqrt(len(x))):.2f} | H1 {R[R.half=='H1'][c].mean():+.2f} H2 {R[R.half=='H2'][c].mean():+.2f}")
    print("\nby drift band:\n",R.groupby('band',observed=True)[['p_settle','p_hedge']].agg(['size','mean']).round(2).to_string())
    print("\nfavourite still won after the drift:",f"{R.won.mean():.0%}","of",len(R),"| vendor claim implies ~45-50% needed at these prices")
    print("\nby competition (n>=5):\n",R.groupby('comp').p_settle.agg(['size','mean']).query('size>=5').round(2).to_string())
PY
