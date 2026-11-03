#!/bin/bash
set -o pipefail
# 325: IS THE TEST ENGINE BROKEN? Positive and negative controls on the two-season tape. If the engine is honest these MUST come out as
# stated; if any does not, the engine is wrong and every "nothing passes" is void.
#   C1 hindsight: back the eventual winner at the kick-off print  -> must be strongly positive (settlement + prices wired right)
#   C2 lookahead: back Over 2.5 at the last real print BEFORE each goal, exit at first print >= goal+2 -> must be strongly positive (minute alignment right)
#   C3 anti-lookahead: same trade 10 minutes before the goal -> must be roughly flat/negative (no leak)
#   C4 random: 20,000 random back/lay trades, hold to settle -> must equal minus commission (about -0.2 to -0.5 per £10) (no bias either way)
#   C5 known literature effect, favourite-longshot bias pre-match: ROI of backing at KO by price band must FALL with price (short prices near -2%, 10+ much worse)
#   C6 friction: what a 5-minute round trip costs at the touch on liq_sample (back at back_px, lay out at lay_px, one tick each) -> the hurdle any scalp must beat
# Each control prints PASS/FAIL against its expected sign and size.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,psycopg2,pandas as pd,numpy as np
from collections import defaultdict
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor(); cur.execute("SET statement_timeout='2400s'")
G=pd.read_sql("""SELECT m.event_id, f.fixture_id, f.season, f.hg, f.ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL""",con)
EV=pd.read_sql("SELECT fixture_id, coalesce(minute,0) AS minute FROM af_events WHERE type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal') AND fixture_id = ANY(%s)",con,params=(list(map(int,G.fixture_id)),))
goals=defaultdict(list)
for r in EV.itertuples(): goals[r.fixture_id].append(int(r.minute))
for k in goals: goals[k].sort()
def tick(p): return 0.01 if p<2 else 0.02 if p<3 else 0.05 if p<4 else 0.1 if p<6 else 0.2 if p<10 else 0.5 if p<20 else 1 if p<30 else 2 if p<50 else 5 if p<100 else 10
def back_settle(p,won): p=p-tick(p); r=10*(p-1) if won else -10.0; return r*0.98 if r>0 else r
def lay_settle(p,won): p=p+tick(p); s=10/(p-1); r=-10.0 if won else s; return r*0.98 if r>0 else r
def back_lay(p,q): p=p-tick(p); q=q+tick(q); r=10*(p/q-1); return r*0.98 if r>0 else r
rng=np.random.default_rng(0)
c1=[];c2=[];c3=[];c4=[];c5=defaultdict(list)
for i in range(0,len(G),1500):
    sub=G.iloc[i:i+1500]
    P=pd.read_sql("SELECT event_id, minute, mkt, sel, ltp::float ltp FROM bf_hist_price WHERE mkt IN ('MO','OU25') AND event_id = ANY(%s) AND minute BETWEEN 0 AND 95 AND ltp>=1.01 AND ltp<1000",con,params=(list(sub.event_id),))
    px={}
    for (eid,mkt,sel),g in P.groupby(['event_id','mkt','sel'],sort=False):
        arr=np.full(97,np.nan); arr[g.minute.values]=g.ltp.values; px.setdefault(eid,{})[(mkt,sel)]=arr
    for g in sub.itertuples():
        b=px.get(g.event_id)
        if not b: continue
        hg,ag=int(g.hg),int(g.ag); res='HOME' if hg>ag else 'AWAY' if ag>hg else 'DRAW'
        # C1 + C5: KO print = first real print at minute 0-2
        for sel in ('HOME','DRAW','AWAY'):
            arr=b.get(('MO',sel))
            if arr is None: continue
            ko=next((arr[m] for m in range(0,3) if not np.isnan(arr[m])),None)
            if ko is None or ko>1000: continue
            won=(sel==res)
            if won: c1.append(back_settle(ko,True))
            band='<1.5' if ko<1.5 else '1.5-2' if ko<2 else '2-3' if ko<3 else '3-5' if ko<5 else '5-10' if ko<10 else '10+'
            c5[band].append(back_settle(ko,won))
            # C4 random: random side, random selection, settle
            if rng.random()<0.3: c4.append(back_settle(ko,won) if rng.random()<0.5 else lay_settle(ko,won))
        # C2 / C3 on Over 2.5
        ov=b.get(('OU25','OVER'))
        if ov is None: continue
        tot=0
        for gm in goals.get(g.fixture_id,[]):
            tot+=1
            if tot>3 or gm<2 or gm>88: continue
            before=next((ov[m] for m in range(gm-1,max(-1,gm-4),-1) if not np.isnan(ov[m])),None)
            after=next((ov[m] for m in range(gm+2,min(97,gm+8)) if not np.isnan(ov[m])),None)
            if tot==3: after=1.01  # third goal settles Over
            if before is not None and after is not None and before>1.01: c2.append(back_lay(before,after))
            b10=next((ov[m] for m in range(gm-10,max(-1,gm-13),-1) if not np.isnan(ov[m])),None) if gm>=12 else None
            a10=next((ov[m] for m in range(gm-8,gm-5) if not np.isnan(ov[m])),None) if gm>=12 else None   # exit still 2+ minutes before the goal
            if b10 is not None and a10 is not None and b10>1.01: c3.append(back_lay(b10,a10))
def rep(name,x,cond,expect):
    x=np.array(x); m=x.mean() if len(x) else float('nan'); ok=cond(m) if len(x) else False
    print(f"{name:60s} n={len(x):6d}  mean per £10 = {m:+7.2f}   expected {expect:28s} -> {'PASS' if ok else 'FAIL'}")
print("== CONTROLS (two-season tape, 12k games)")
rep("C1 hindsight: back the winner at KO",c1,lambda m:m>5,"strongly positive (> +5)")
rep("C2 lookahead: back Over 2.5 just before a goal",c2,lambda m:m>3,"strongly positive (> +3)")
rep("C3 anti-lookahead: same trade 10 min before the goal, out at -8",c3,lambda m:-1.5<m<1.5,"roughly flat (between -1.5 and +1.5)")
rep("C4 random trades, hold to settle",c4,lambda m:-1.0<m<0.0,"minus commission (between -1 and 0)")
print("\n== C5 favourite-longshot gradient, backing at KO by price band (literature: ROI falls as price rises)")
rows=[(b,len(v),np.mean(v)) for b,v in c5.items()]; order=['<1.5','1.5-2','2-3','3-5','5-10','10+']
rows=sorted(rows,key=lambda r:order.index(r[0]));
for b,n,m in rows: print(f"   {b:6s} n={n:6d}  {m:+6.2f} per £10")
mono=all(rows[i][2]>=rows[i+1][2]-0.6 for i in range(len(rows)-1)); print("   gradient broadly falling:", "PASS" if (rows[0][2]>rows[-1][2]) else "FAIL")
# C6 friction on the recorder
F=pd.read_sql("""WITH s AS (SELECT event_name, mkt, sel, ts, back_px::float b, lay_px::float l, lead(lay_px::float,5) OVER (PARTITION BY event_name,mkt,sel ORDER BY ts) l5, lead(ts,5) OVER (PARTITION BY event_name,mkt,sel ORDER BY ts) ts5
  FROM liq_sample WHERE ts>now()-interval '5 days' AND mkt IN ('MO','OU25') AND back_px>1.05 AND lay_px<30 AND minute BETWEEN 5 AND 80)
  SELECT mkt, avg(10*((b-0.01)/(l5+0.01)-1)) cost_per10, avg((l-b)/b*100) spread_pct, count(*) n FROM s WHERE l5 IS NOT NULL AND ts5-ts BETWEEN interval '3 min' AND interval '8 min' GROUP BY mkt""",con)
print("\n== C6 friction: back now at back_px, lay out ~5 min later at lay_px, no view on direction (what any 5-min scalp must beat)")
print(F.round(3).to_string(index=False))
PY
