#!/bin/bash
# 192: (191's market filter was self-contradicting — minute<=5 rows asked for max minute>=88 — so it tested nothing; fixed.) OUT-OF-SAMPLE ON LIVE LADDERS. The price-only sweep's surviving family is "lay the draw in a level game from 46'/60'/75' (draw
# 1.5-2.5), exit after the next goal" at ~+£2 per £10 on two seasons of historical LTPs with an assumed 2% spread. The live liquidity
# recorder has the REAL back/lay ladders for every in-play Match Odds market since 20 Oct (~1,000 markets tracked from kick-off) and
# the goal reopen events (liq_goal_depth). Same rule on that data, with the actual lay price at entry and the actual back price at exit,
# 2% commission only: n, mean, win rate per trigger minute, and the xG-dominance rule where ip_stats is attached. Also appends the
# OPEN-game inverse (lay Over 2.5 / back Under 2.5 when xG is high) to the stats sweep grammar, since backing overs there lost 10-15%.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys, psycopg2, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
pd.set_option('display.width',220)
con=psycopg2.connect(DB,sslmode='require'); COMM=0.02
mk=pd.read_sql("SELECT market_id FROM liq_sample WHERE mkt='MO' GROUP BY market_id HAVING min(minute)<=5 AND max(minute)>=88",con); mids=list(mk.market_id); print("markets tracked from kick-off to 88'+:",len(mids))
S=pd.read_sql("SELECT market_id, event_name, competition, ts, minute, sel, ltp::float ltp, back_px::float bp, lay_px::float lp, back_sz::float bsz, lay_sz::float lsz, total_matched::float tm FROM liq_sample WHERE mkt='MO' AND market_id = ANY(%s) ORDER BY market_id, ts",con,params=(mids,))
G=pd.read_sql("SELECT market_id, min(goal_ts) goal_ts, minute FROM liq_goal_depth WHERE mkt='MO' AND market_id = ANY(%s) GROUP BY market_id, minute",con,params=(mids,))
goals={m:sorted(g.goal_ts.tolist()) for m,g in G.groupby('market_id')}
rows=[]
for mid,g in S.groupby('market_id',sort=False):
    d=g[g.sel=='DRAW']; h=g[g.sel=='HOME']; a=g[g.sel=='AWAY']
    if d.empty or h.empty or a.empty: continue
    gl=goals.get(mid,[])
    # result from final prices
    last=g[g.ts==g.ts.max()]; fin={r.sel:r.ltp for r in last.itertuples() if pd.notna(r.ltp)}
    if not fin: continue
    wsel=min(fin,key=fin.get); winner=wsel if fin[wsel]<=1.15 else None
    for trig in (46,60,75):
        e=d[(d.minute>=trig)&(d.minute<=trig+2)&d.lp.notna()]
        if e.empty: continue
        r0=e.iloc[0]
        if any(t<r0.ts for t in gl): continue              # not 0-0 (a goal already recorded)
        lo=min(h[h.ts<=r0.ts].ltp.dropna().iloc[-1] if len(h[h.ts<=r0.ts].ltp.dropna()) else 99, a[a.ts<=r0.ts].ltp.dropna().iloc[-1] if len(a[a.ts<=r0.ts].ltp.dropna()) else 99)
        if lo<1.30: continue                                 # hidden goal: market not level
        lay=r0.lp
        if not (1.5<=lay<=2.5): continue
        if (r0.lsz or 0)<20: continue                        # need at least £20 on the lay side
        nxt=[t for t in gl if t>r0.ts]
        if nxt:
            x=d[(d.ts>=nxt[0]+pd.Timedelta(seconds=120))&d.bp.notna()]
            if x.empty: continue
            back=x.iloc[0].bp; p=10*(1-lay/back); p=p*(1-COMM) if p>0 else p; how='goal'
        else:
            if winner is None: continue
            p=(-10*(lay-1)) if winner=='DRAW' else 10*(1-COMM); how='settle'
        rows.append(dict(market_id=mid,event=g.event_name.iloc[0],comp=g.competition.iloc[0],trig=trig,lay=lay,lay_sz=r0.lsz,how=how,p=round(p,2),tm=r0.tm))
R=pd.DataFrame(rows); print("\nLIVE LADDER TEST — lay the draw at 1.5-2.5 in a level game, exit 2 min after the next goal (real lay price in, real back price out, 2% comm):")
if len(R):
    print(R.groupby('trig').p.agg(n='size',mean='mean',win=lambda s:(s>0).mean(),total='sum').round(2).to_string())
    print("\nall:",len(R),"trades | mean per £10:",round(R.p.mean(),2),"| win",f"{(R.p>0).mean():.0%}","| total £",round(R.p.sum(),1)," | backtest said ~+2.2 per £10, 74-81% win")
    print("\nby competition (n>=5):\n",R.groupby('comp').p.agg(['size','mean']).query('size>=5').round(2).sort_values('mean',ascending=False).to_string())
    print("\nexit type:",R.how.value_counts().to_dict(),"| median lay size at entry £",R.lay_sz.median())
    print("\nsample:\n",R.sample(min(8,len(R)),random_state=1)[['event','trig','lay','how','p']].to_string(index=False))
else: print("no qualifying trades")
PY
