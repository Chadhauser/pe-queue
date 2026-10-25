#!/bin/bash
# 211: LIVE-LADDER REPLAY of the strongest honest cell family: lay Over 2.5 late in a game with <= 1 goal (true-goal history 55'-75':
# +0.8 to +5.3 per £10 in every band and minute, t 3-7, exits +10/+20/next goal). Recorder's real OU25 ladders since 20 Oct: entry at
# the real OVER lay price at 55/60/65/70/75 (>= £10 available), goal count from book jumps in the draw (<= 1 before entry; a goal =
# draw best back +25% sane-to-sane) cross-checked against the OU25 price itself (a 2-goal game would show Over 2.5 under 1.5), exit at
# the OVER back price 20 min later, or 2 min after the next goal (OVER back falls 30%+), else settle from the MO/OU final book.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys, psycopg2, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
pd.set_option('display.width',220); COMM=0.02; JUMP=1.25
con=psycopg2.connect(DB,sslmode='require')
mk=pd.read_sql("SELECT market_id FROM liq_sample WHERE mkt='MO' GROUP BY market_id HAVING min(minute)<=5 AND max(minute)>=88",con); mids=list(mk.market_id); print("markets:",len(mids))
A=pd.read_sql("SELECT market_id, event_name, competition, ts, minute, mkt, sel, back_px::float bp, lay_px::float lp, lay_sz::float lsz, total_matched::float tm FROM liq_sample WHERE mkt IN ('MO','OU25') AND market_id = ANY(%s) AND back_px IS NOT NULL ORDER BY market_id, ts",con,params=(mids,))
A['sane']=A.lp.notna()&(A.lp<=A.bp*1.2)
rows=[]
for mid,g in A.groupby('market_id',sort=False):
    d=g[(g.mkt=='MO')&(g.sel=='DRAW')&g.sane].copy(); o=g[(g.mkt=='OU25')&(g.sel=='OVER')&g.sane].copy()
    if len(d)<10 or len(o)<10: continue
    d['pb']=d.bp.shift(); d['pl']=d.lp.shift(); jumps=d[(d.bp>=d.pb*JUMP)&(d.bp>=d.pl*JUMP)].ts.tolist()
    o['pb']=o.bp.shift(); drops=o[o.bp<=o.pb*0.7].ts.tolist()
    late=o[o.minute>=85]; fin_over=late.iloc[-1].bp if len(late) else None    # Over 2.5 back price near the end: <=1.15 means over landed
    for trig in (55,60,65,70,75):
        e=o[(o.minute>=trig)&(o.minute<=trig+2)]
        if e.empty: continue
        r0=e.iloc[0]; ng=sum(1 for t in jumps if t<=r0.ts)
        if ng>1: continue
        lay=r0.lp
        if not (1.6<=lay<=5.0) or (r0.lsz or 0)<10: continue
        if ng==0 and lay<1.6: continue
        gl=[t for t in drops+jumps if t>r0.ts]; gts=min(gl) if gl else None
        t20=r0.ts+pd.Timedelta(minutes=20)
        if gts is not None and gts<t20:
            x=o[o.ts>=gts+pd.Timedelta(seconds=120)]
            if x.empty: continue
            back=x.iloc[0].bp; how='goal'
        else:
            x=o[o.ts>=t20]
            if not x.empty: back=x.iloc[0].bp; how='t20'
            else:
                if fin_over is None: continue
                p=(-10*(lay-1)) if fin_over<=1.15 else 10*(1-COMM); rows.append(dict(event=g.event_name.iloc[0],comp=g.competition.iloc[0],trig=trig,ng=ng,lay=lay,how='settle',p=round(p,2))); continue
        p=10*(1-lay/back); p=p*(1-COMM) if p>0 else p
        rows.append(dict(event=g.event_name.iloc[0],comp=g.competition.iloc[0],trig=trig,ng=ng,lay=lay,how=how,p=round(p,2)))
R=pd.DataFrame(rows); print("\nLIVE LADDER — lay Over 2.5 at 55-75 with <=1 goal, exit +20 min / 2 min after a goal (real lay in, real back out, 2% comm):",len(R),"trades")
if len(R):
    print(R.groupby('trig').p.agg(n='size',mean='mean',win=lambda s:(s>0).mean(),total='sum').round(2).to_string())
    print("\nby goals-so-far:\n",R.groupby('ng').p.agg(['size','mean']).round(2).to_string())
    print("\nby lay band:\n",R.assign(band=pd.cut(R.lay,[1.5,2.5,3.5,5])).groupby('band',observed=True).p.agg(['size','mean']).round(2).to_string())
    x=R.p; print("\nall:",len(R),"| mean per £10",round(x.mean(),2),"| win",f"{(x>0).mean():.0%}","| total £",round(x.sum(),1),"| t",round(x.mean()/(x.std(ddof=1)/np.sqrt(len(x))),2),"| history said +1.2 to +2.4 (60'-70', band 2.5-5)")
    print("exit type:",R.how.value_counts().to_dict())
    print("\nby competition (n>=8):\n",R.groupby('comp').p.agg(['size','mean']).query('size>=8').round(2).sort_values('mean',ascending=False).to_string())
PY
