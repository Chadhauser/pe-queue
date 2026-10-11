#!/bin/bash
# 031: "PEOPLE MAKE MONEY FROM xG TRADING" — tested on data we already hold and never joined to prices:
# goal_backfill_predictions = minute-by-minute in-play xG + shots on target for 1,046 fixtures Aug 2025-May 2026 (17 leagues).
# Joined to the Betfair minute tape (MO + OU2.5). Question: when live xG says "goal coming" and the price has not moved,
# is the next-10-min goal rate and the price move better than the price implies? Strict: fresh prices, 2pct spread, 2pct comm.
# One season only, so train = Aug-Dec 2025, test = Jan-May 2026 (time split, no peeking).
cd /root/pe-scan && cat > xg_trading_test.py <<'PYFILE'
import re, sys, math, datetime, collections, psycopg2, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
SPREAD=0.02; COMM=0.02
def norm(s): return re.sub(r'[^a-z]','',(s or '').lower().split(' ')[0])
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor()
X=pd.read_sql("""SELECT g.fixture_id, h.kickoff::date AS d, h.home_team, h.away_team, h.league_name, g.minute, g.score_home, g.score_away, g.home_sot, g.away_sot,
  g.xg_home, g.xg_away, g.goal_within_10, g.next_goal_minute FROM goal_backfill_predictions g JOIN hist_fixtures h ON h.fixture_id=g.fixture_id
  WHERE g.xg_home IS NOT NULL ORDER BY g.fixture_id, g.minute""",con)
print("xG rows",len(X),"fixtures",X.fixture_id.nunique(),"minutes per fixture ~",round(len(X)/X.fixture_id.nunique(),1))
X['xg_tot']=X.xg_home+X.xg_away; X['sot_tot']=X.home_sot.fillna(0)+X.away_sot.fillna(0)
X['xg_prev']=X.groupby('fixture_id').xg_tot.shift(2)  # ~10 min earlier (rows are ~5 min apart)
X['xg_last10']=(X.xg_tot-X.xg_prev).clip(lower=0)
X['xg_rate']=X.xg_tot/X.minute.clip(lower=1)
# goals from the tape join source (fts_advanced_results) for exits
cur.execute("SELECT match_date, home_team, away_team, goal_times FROM fts_advanced_results WHERE match_date>='2025-08-01'")
G={}
for d,h,a,gt in cur.fetchall():
    d=datetime.date.fromisoformat(str(d)[:10]); goals=[]
    for t in (gt or '').split('|'):
        mm=re.match(r"\s*(\d+)(?:\+(\d+))?\((H|A)\)",t)
        if mm: goals.append(int(mm.group(1))+int(mm.group(2) or 0))
    G[(d,norm(h),norm(a))]=sorted(goals)
# index xG rows by (date, home, away)
K={}
for (fid,d,h,a),grp in X.groupby(['fixture_id','d','home_team','away_team']):
    K[(d,norm(h),norm(a))]=grp.set_index('minute')
print("xG fixtures keyed",len(K))
con_s=psycopg2.connect(DB,sslmode='require'); scur=con_s.cursor(name='tape'); scur.itersize=50000
scur.execute("SELECT event_id,hw,aw,m,minute,mkt,sel,ltp FROM bf_hist_price WHERE ht_offset IS NOT NULL AND mkt IN ('MO','OU25') AND m>='2025-08-01' ORDER BY event_id,m")
rows=[]; n_seen=0; n_j=0
def px_at(px,mkt,sel,t,tol=0):
    d=px.get((mkt,sel),{})
    for k in range(t,t-tol-1,-1):
        if k in d: return d[k]
    return None
def tp(side,e,x):
    if side=='back': p=(e*(1-SPREAD))/(x*(1+SPREAD))-1
    else: p=1-(e*(1+SPREAD))/(x*(1-SPREAD))
    return p*(1-COMM) if p>0 else p
def process(rs):
    global n_seen,n_j
    n_seen+=1
    hw,aw=norm(rs[0][1]),norm(rs[0][2]); d=rs[0][3].date()
    key=next((k for k in ((d,hw,aw),(d-datetime.timedelta(days=1),hw,aw),(d+datetime.timedelta(days=1),hw,aw)) if k in K),None)
    if n_seen==300:
        print(f"SELF-CHECK after 300 events: {n_j} joined",flush=True)
    if not key: return
    n_j+=1; xg=K[key]; goals=G.get(key,[])
    px=collections.defaultdict(dict)
    for _,_,_,_,minute,mkt,sel,ltp in rs: px[(mkt,sel)][int(minute)]=float(ltp)
    for t,r in xg.iterrows():
        t=int(t)
        if t<10 or t>80: continue
        if any(0<=t-g<3 for g in goals): continue
        sh,sa=int(r.score_home or 0),int(r.score_away or 0)
        o=px_at(px,'OU25','OVER',t); dr=px_at(px,'MO','DRAW',t)
        if not o and not dr: continue
        nxt=[g for g in goals if g>t]
        gw10=bool(nxt and nxt[0]<=t+10)
        # exits: goal+3 (fresh, tol 2) else t+10 (fresh, tol 2)
        xt=(nxt[0]+3) if gw10 else t+10
        o_x=px_at(px,'OU25','OVER',xt,2); d_x=px_at(px,'MO','DRAW',xt,2)
        rows.append((key[0],t,sh,sa,sh+sa,r.xg_tot,r.xg_last10,r.xg_rate,r.sot_tot,o,o_x,dr,d_x,gw10,
                     tp('back',o,o_x) if (o and o_x and o>1.01) else np.nan, tp('lay',dr,d_x) if (dr and d_x and dr>1.01 and sh==sa) else np.nan))
buf=[]; last=None
for r in scur:
    if last is not None and r[0]!=last: process(buf); buf=[]
    buf.append(r); last=r[0]
if buf: process(buf)
D=pd.DataFrame(rows,columns=['d','t','sh','sa','goals','xg_tot','xg_last10','xg_rate','sot','over_px','over_exit','draw_px','draw_exit','goal_in_10','pnl_back_over','pnl_lay_draw'])
print(f"events seen {n_seen}, joined to xG {n_j}, state rows {len(D)}")
if len(D)<500: sys.exit("too few joined rows")
D['split']=np.where(pd.to_datetime(D.d)<pd.Timestamp('2026-01-01'),'train Aug-Dec','test Jan-May')
D['implied_over']=1/D.over_px
# xG bands relative to minute: quartiles of xg_rate within the TRAIN split, applied to both
q=D[D.split=='train Aug-Dec'].xg_rate.quantile([0.25,0.5,0.75]).values
D['xg_q']=pd.cut(D.xg_rate,[-1,q[0],q[1],q[2],99],labels=['Q1 low','Q2','Q3','Q4 high'])
q2=D[D.split=='train Aug-Dec'].xg_last10.quantile([0.5,0.75,0.9]).values
D['recent_q']=pd.cut(D.xg_last10,[-1,q2[0],q2[1],q2[2],99],labels=['<med','med-75','75-90','top10'])
pd.set_option('display.width',250)
print("\n=== 1. Does live xG rate predict a goal in the next 10 min, beyond the price? (goal rate by xG quartile, with the market's Over 2.5 implied prob as control) ===")
T=D.groupby(['xg_q','split'],observed=True).agg(n=('goal_in_10','size'),goal10=('goal_in_10','mean'),implied_over=('implied_over','mean')).round(3)
print(T.unstack('split').to_string())
print("\n=== 2. Same, by RECENT xG (last ~10 min) — the 'pressure building' signal xG traders use ===")
print(D.groupby(['recent_q','split'],observed=True).agg(n=('goal_in_10','size'),goal10=('goal_in_10','mean'),implied_over=('implied_over','mean')).round(3).unstack('split').to_string())
print("\n=== 3. TRADE: back Over 2.5 at t, exit goal+3 or t+10. P&L per £100 by xG quartile, LEVEL scores only ===")
L=D[D.sh==D.sa]
print(L.groupby(['xg_q','split'],observed=True).pnl_back_over.agg(['size','mean']).assign(mean=lambda x:(100*x['mean']).round(1)).unstack('split').to_string())
print("\n=== 4. TRADE: lay the DRAW at t (level scores), exit goal+3 or t+10, per £100 stake, by recent xG ===")
print(L.groupby(['recent_q','split'],observed=True).pnl_lay_draw.agg(['size','mean']).assign(mean=lambda x:(100*x['mean']).round(1)).unstack('split').to_string())
print("\n=== 5. Combined 'xG trader' rule: level score, minute 20-75, xg_rate Q4 AND recent xG top-25pct, back Over 2.5 ===")
R=L[(L.t.between(20,75))&(L.xg_q=='Q4 high')&(L.recent_q.isin(['75-90','top10']))]
print(R.groupby('split').agg(n=('pnl_back_over','size'),per100=('pnl_back_over',lambda x:round(100*x.mean(),1)),goal10=('goal_in_10','mean')).round(3).to_string())
print("Same rule, lay draw:"); print(R.groupby('split').agg(n=('pnl_lay_draw','size'),per100=('pnl_lay_draw',lambda x:round(100*x.mean(),1))).to_string())
print("\n=== 6. The opposite: low xG (Q1), level, 20-75: back UNDER (= lay Over) ===")
U=L[(L.t.between(20,75))&(L.xg_q=='Q1 low')]
print(U.groupby('split').agg(n=('pnl_back_over','size'),lay_over_per100=('pnl_back_over',lambda x:round(-100*x.mean(),1)),goal10=('goal_in_10','mean')).round(3).to_string())
print("\nVERDICT RULE: an xG rule is a candidate only if per100 > +2 in BOTH halves of the season with n>=150 each. Sections 1-2 say whether xG carries information the price lacks; 3-6 say whether it pays after costs.")
PYFILE
python3 xg_trading_test.py
