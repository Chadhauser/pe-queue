#!/bin/bash
# 033: xG TRADING TEST v2 on UNDERSTAT shot-by-shot xG (top-5 leagues, 2024/25 + 2025/26, ~3,600 matches) joined to the Betfair
# minute tape. Same questions and costs as 031 but ten times the data and a true two-season train/test. Waits (exit 75) for 032.
N=$(python3 - <<'PY'
import sys, psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require').cursor(); c.execute("SELECT count(DISTINCT understat_id) FROM understat_shots"); print(c.fetchone()[0])
PY
)
echo "understat matches with shots: $N"; [ "${N:-0}" -lt 3000 ] && { echo "WAITING for 032 (need 3000+)"; exit 75; }
cd /root/pe-scan && cat > xg_trading_test_v2.py <<'PYFILE'
import re, sys, math, datetime, collections, psycopg2, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
SPREAD=0.02; COMM=0.02
def norm0(s): return re.sub(r'[^a-z]','',(s or '').lower().split(' ')[0])
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor()
M=pd.read_sql("SELECT understat_id, league, season, match_date::date AS d, home_team, away_team, home_goals, away_goals FROM understat_matches",con)
S=pd.read_sql("SELECT understat_id, minute, team_side, xg, result FROM understat_shots",con)
print("understat matches",len(M),"shots",len(S))
ALIAS={'manchester city':'man city','manchester united':'man utd','nottingham forest':'nottm forest','wolverhampton wanderers':'wolves','sheffield united':'sheff utd',
 'paris saint germain':'psg','borussia dortmund':'dortmund','borussia m.gladbach':'mgladbach','borussia monchengladbach':'mgladbach','bayer leverkusen':'leverkusen',
 'rasenballsport leipzig':'rb leipzig','fc cologne':'koln','fc koln':'koln','ac milan':'milan','hellas verona':'verona','parma calcio 1913':'parma','athletic club':'athletic bilbao',
 'real betis':'betis','fc st. pauli':'st pauli','vfb stuttgart':'stuttgart','vfl wolfsburg':'wolfsburg','vfl bochum':'bochum','tsg hoffenheim':'hoffenheim','sc freiburg':'freiburg',
 'fc augsburg':'augsburg','sv werder bremen':'werder bremen','1. fc heidenheim':'heidenheim','fc heidenheim':'heidenheim','1. fc union berlin':'union berlin','fsv mainz 05':'mainz','mainz 05':'mainz',
 'holstein kiel':'kiel','saint-etienne':'st etienne','newcastle united':'newcastle','west ham':'west ham','brighton':'brighton','tottenham':'tottenham','leeds':'leeds','deportivo alaves':'alaves','rayo vallecano':'rayo vallecano','real sociedad':'real sociedad','atletico madrid':'atletico madrid','celta vigo':'celta vigo','las palmas':'las palmas','real valladolid':'valladolid'}
def nname(s):
    s=re.sub(r'[^a-z0-9 .\-]','',(s or '').lower()).strip()
    s=ALIAS.get(s,s)
    return re.sub(r'[^a-z]','',s.split(' ')[0])
# minute-by-minute timeline every 5 min from shots
rows=[]
S['sot']=S.result.isin(['Goal','SavedShot'])
for uid,g in S.groupby('understat_id'):
    g=g.sort_values('minute')
    for t in range(10,81,5):
        past=g[g.minute<=t]
        rec=g[(g.minute<=t)&(g.minute>t-10)]
        xh=past[past.team_side=='H'].xg.sum(); xa=past[past.team_side=='A'].xg.sum()
        gh=int((past.result=='Goal')[past.team_side=='H'].sum()); ga=int((past.result=='Goal')[past.team_side=='A'].sum())
        rows.append((uid,t,gh,ga,xh,xa,xh+xa,rec.xg.sum(),(xh+xa)/t,int(past.sot.sum())))
X=pd.DataFrame(rows,columns=['understat_id','minute','score_home','score_away','xg_home','xg_away','xg_tot','xg_last10','xg_rate','sot_tot'])
X=X.merge(M,on='understat_id')
X['fixture_id']=X.understat_id
print("timeline rows",len(X),"fixtures",X.fixture_id.nunique())
norm=nname
# goals from the tape join source (fts_advanced_results) for exits
cur.execute("SELECT match_date, home_team, away_team, goal_times FROM fts_advanced_results WHERE match_date>='2024-08-01'")
G={}
for d,h,a,gt in cur.fetchall():
    d=datetime.date.fromisoformat(str(d)[:10]); goals=[]
    for t in (gt or '').split('|'):
        mm=re.match(r"\s*(\d+)(?:\+(\d+))?\((H|A)\)",t)
        if mm: goals.append(int(mm.group(1))+int(mm.group(2) or 0))
    G[(d,norm0(h),norm0(a))]=sorted(goals)
# index xG rows by (date, home, away)
K={}
for (fid,d,h,a),grp in X.groupby(['fixture_id','d','home_team','away_team']):
    K[(d,norm(h),norm(a))]=grp.set_index('minute')
print("xG fixtures keyed",len(K))
con_s=psycopg2.connect(DB,sslmode='require'); scur=con_s.cursor(name='tape'); scur.itersize=50000
scur.execute("SELECT event_id,hw,aw,m,minute,mkt,sel,ltp FROM bf_hist_price WHERE ht_offset IS NOT NULL AND mkt IN ('MO','OU25') ORDER BY event_id,m")
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
    hw,aw=norm0(rs[0][1]),norm0(rs[0][2]); d=rs[0][3].date()
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
D['split']=np.where(pd.to_datetime(D.d)<pd.Timestamp('2025-07-01'),'train 2024/25','test 2025/26')
D['implied_over']=1/D.over_px
# xG bands relative to minute: quartiles of xg_rate within the TRAIN split, applied to both
q=D[D.split=='train 2024/25'].xg_rate.quantile([0.25,0.5,0.75]).values
D['xg_q']=pd.cut(D.xg_rate,[-1,q[0],q[1],q[2],99],labels=['Q1 low','Q2','Q3','Q4 high'])
q2=D[D.split=='train 2024/25'].xg_last10.quantile([0.5,0.75,0.9]).values
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
print("\nVERDICT RULE: an xG rule is a candidate only if per100 > +2 in BOTH seasons with n>=150 each. Sections 1-2 say whether xG carries information the price lacks; 3-6 say whether it pays after costs.")
PYFILE
python3 xg_trading_test_v2.py
