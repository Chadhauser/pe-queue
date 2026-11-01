#!/bin/bash
set -o pipefail
# 304: THE BORING MONEY AT SCALE — the five clock-based in-and-out patterns from the Chelsea v Man Utd tape, tested on every game
# in the two-season Betfair tape (bf_hist_price 1-min LTP, 12k games mapped to API-Football goal minutes). Entry and exit on the
# clock only, never on a goal prediction. One tick adverse both ends, 2% commission, £10 per trade. Season 2024 / 2025 = halves.
#   P1  0-0 at KO: lay Over 2.5 at 1', back out at 40' (or at the first goal's next minute if earlier)
#   P2  0-0 at KO: back the Draw at 1', lay out at 43' (or at first goal +1)
#   P3  after ANY goal before 75': lay Over 2.5 one minute after, back out 10 minutes later (or at next goal +1)
#   P4  after a goal gives a lead before 75': back the leader one minute after, lay out when 10 ticks shorter or after 10 minutes / next goal
#   P5  two-goal lead at 60-70': lay Over 2.5, hold to 88' (or next goal +1)
# Also per pre-match favourite band and league group. Survivors printed: n>=300, t>=3.5, both seasons >0.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,psycopg2,pandas as pd,numpy as np
from collections import defaultdict
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor(); cur.execute("SET statement_timeout='3000s'")
try: cur.execute("SELECT count(*) FROM af_price_map"); n=cur.fetchone()[0]
except Exception: print("map missing"); sys.exit(75)
if n<1000: sys.exit(75)
G=pd.read_sql("""SELECT m.event_id, f.fixture_id, f.season, f.league, f.hg, f.ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL""",con)
EV=pd.read_sql("SELECT fixture_id, coalesce(minute,0) AS minute, is_home, detail FROM af_events WHERE type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal') AND fixture_id = ANY(%s)",con,params=(list(map(int,G.fixture_id)),))
goals=defaultdict(list)
for r in EV.itertuples():
    side=('h' if r.is_home else 'a') if r.detail!='Own Goal' else ('a' if r.is_home else 'h'); goals[r.fixture_id].append((int(r.minute),side))
for k in goals: goals[k].sort()
def tick(p): return 0.01 if p<2 else 0.02 if p<3 else 0.05 if p<4 else 0.1 if p<6 else 0.2 if p<10 else 0.5 if p<20 else 1 if p<30 else 2 if p<50 else 5 if p<100 else 10
def back_lay(p,q): p=p-tick(p); q=q+tick(q); r=10*(p/q-1); return r*0.98 if r>0 else r
def lay_back(p,q): p=p+tick(p); q=max(1.01,q-tick(q)); r=10*(1-p/q); return r*0.98 if r>0 else r
def favband(f): return '<1.5' if f<1.5 else '1.5-2' if f<2 else '2-3' if f<3 else '3+'
rows=[]
for i in range(0,len(G),1500):
    sub=G.iloc[i:i+1500]
    P=pd.read_sql("SELECT event_id, minute, mkt, sel, ltp::float ltp FROM bf_hist_price WHERE mkt IN ('MO','OU25') AND event_id = ANY(%s) AND minute BETWEEN 0 AND 95 AND ltp>1.01 AND ltp<200",con,params=(list(sub.event_id),))
    px={}
    for (eid,mkt,sel),g in P.groupby(['event_id','mkt','sel'],sort=False):
        arr=np.full(97,np.nan); arr[g.minute.values]=g.ltp.values; last=np.nan; age=99
        for m in range(97):
            if not np.isnan(arr[m]): last=arr[m]; age=0
            else:
                age+=1
                if age<=3: arr[m]=last
        px.setdefault(eid,{})[(mkt,sel)]=arr
    for g in sub.itertuples():
        b=px.get(g.event_id)
        if not b: continue
        ov=b.get(('OU25','OVER')); dr=b.get(('MO','DRAW')); ho=b.get(('MO','HOME')); aw=b.get(('MO','AWAY'))
        if ov is None or dr is None or ho is None or aw is None or np.isnan(ho[1]) or np.isnan(aw[1]): continue
        fb=favband(min(ho[1],aw[1])); gl=goals.get(g.fixture_id,[]); lg=g.league; se=int(g.season)
        def first_goal_after(m): return next((gm for gm,s in gl if gm>m),None)
        def ok(*v): return all(not np.isnan(x) for x in v)
        # P1 / P2
        fg=first_goal_after(0)
        x=min(40, fg+1) if fg is not None else 40
        if ok(ov[1],ov[x]): rows.append(('P1_lay_over_0-0_to40',fb,lg,se,lay_back(ov[1],ov[x]),fg is not None and fg<=40))
        x=min(43, fg+1) if fg is not None else 43
        if ok(dr[1],dr[x]): rows.append(('P2_back_draw_0-0_to43',fb,lg,se,back_lay(dr[1],dr[x]),fg is not None and fg<=43))
        # P3 / P4 per goal
        h=a=0
        for gm,s in gl:
            if s=='h': h+=1
            else: a+=1
            if gm>=75 or gm+1>95: continue
            ng=first_goal_after(gm); e=gm+1
            x=min(gm+11, ng+1) if ng is not None else gm+11
            if x<=95 and ok(ov[e],ov[x]): rows.append(('P3_lay_over_after_goal_10m',fb,lg,se,lay_back(ov[e],ov[x]),ng is not None and ng<=gm+10))
            if h!=a:
                L=ho if h>a else aw
                if ok(L[e]):
                    p=L[e]; tgt=p;
                    for _ in range(10): tgt=tgt-tick(tgt-0.001)
                    xm=None
                    for mm in range(e+1,min(gm+11,95)+1):
                        if ng is not None and mm>ng: break
                        if ok(L[mm]) and L[mm]<=tgt: xm=mm; break
                    if xm is None: xm=min(gm+11, ng+1) if ng is not None else gm+11
                    if xm<=95 and ok(L[xm]): rows.append(('P4_back_leader_10ticks',fb,lg,se,back_lay(p,L[xm]),ng is not None and ng<=xm))
        # P5 two-goal lead at 60-70
        h=a=0; done=False
        for m in range(60,71):
            h=sum(1 for gm,s in gl if gm<=m and s=='h'); a=sum(1 for gm,s in gl if gm<=m and s=='a')
            if abs(h-a)>=2 and not done:
                ng=first_goal_after(m); x=min(88, ng+1) if ng is not None else 88
                if ok(ov[m+1],ov[x]): rows.append(('P5_lay_over_2goal_lead_to88',fb,lg,se,lay_back(ov[m+1],ov[x]),ng is not None and ng<=88))
                done=True
    print(f"  {min(i+1500,len(G))}/{len(G)} | trades {len(rows)}",flush=True)
D=pd.DataFrame(rows,columns=['pattern','fav','league','season','pnl','goal_hit'])
def t(x): return x.mean()/(x.std(ddof=1)/len(x)**0.5) if len(x)>1 and x.std(ddof=1)>0 else 0
def rep(dims):
    g=D.groupby(dims).agg(n=('pnl','size'),per10=('pnl','mean'),t=('pnl',t),goal_hit=('goal_hit','mean'),h1=('pnl',lambda x:x[D.loc[x.index,'season']==2024].mean()),h2=('pnl',lambda x:x[D.loc[x.index,'season']==2025].mean())).round(3)
    return g[g.n>=300]
cur.execute("DROP TABLE IF EXISTS boring_results; CREATE TABLE boring_results (level TEXT, pattern TEXT, fav TEXT, league TEXT, n INT, per10 NUMERIC, t NUMERIC, goal_hit NUMERIC, h1 NUMERIC, h2 NUMERIC)"); con.commit()
allr=[]
for dims in (['pattern'],['pattern','fav'],['pattern','league'],['pattern','fav','league']):
    r=rep(dims).reset_index(); r['level']='+'.join(dims)
    for c in ('fav','league'):
        if c not in r: r[c]=None
    allr.append(r)
    for x in r.itertuples(): cur.execute("INSERT INTO boring_results VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)",(x.level,x.pattern,x.fav,x.league,int(x.n),float(x.per10),float(x.t),float(x.goal_hit),float(x.h1) if pd.notna(x.h1) else None,float(x.h2) if pd.notna(x.h2) else None))
con.commit()
R=pd.concat(allr,ignore_index=True)
print("\n== the five patterns, all games (per £10, one tick adverse, 2% comm)"); print(R[R.level=='pattern'][['pattern','n','per10','t','goal_hit','h1','h2']].to_string(index=False))
S=R[(R.t>=3.5)&(R.h1>0)&(R.h2>0)&(R.per10>=0.15)].sort_values('t',ascending=False)
print(f"\n== SURVIVORS: {len(S)}"); print(S[['level','pattern','fav','league','n','per10','t','h1','h2']].head(40).to_string(index=False) if len(S) else "none")
PY
