#!/bin/bash
# 028: ROBUSTNESS of the one state that survived scan v4: BACK OVER 1.5 at 0-0, minutes 20-34, top-5 league, home pre-match
# favourite (<2.2). Held to FT. Fresh LTP at entry (traded that minute), 2pct spread, 2pct comm. One trade per match (first qualifying
# minute). Splits: league, entry minute, price band, home price band, month, and the same rule in tier2 (where v4 showed the
# OPPOSITE sign - if that is real the tier1 result is suspect). Plus 5-19 band and "any favourite" variants. Peter decides after this.
cd /root/pe-scan && cat > ou15_robust.py <<'PYFILE'
import re, sys, math, datetime, collections, psycopg2, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
SPREAD=0.02; COMM=0.02
def norm(s): return re.sub(r'[^a-z]','',(s or '').lower().split(' ')[0])
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor()
cur.execute("SELECT match_date, competition, home_team, away_team, goal_times, mo_home_back, ft_home, ft_away FROM fts_advanced_results WHERE match_date>='2024-08-01'")
TOP={'English Premier League','Spanish Primera Division','Italian Serie A','German Bundesliga','French Ligue 1'}
G={}
for d,lg,h,a,gt,ph,fh,fa in cur.fetchall():
    d=datetime.date.fromisoformat(str(d)[:10]); goals=[]
    for t in (gt or '').split('|'):
        mm=re.match(r"\s*(\d+)(?:\+(\d+))?\((H|A)\)",t)
        if mm: goals.append(int(mm.group(1))+int(mm.group(2) or 0))
    try: ph=float(ph)
    except: ph=None
    G[(d,norm(h),norm(a))]=(sorted(goals),int(fh)+int(fa),lg,ph)
rows=[]; n_ev=0; n_seen=0
con_s=psycopg2.connect(DB,sslmode='require'); scur=con_s.cursor(name='tape'); scur.itersize=50000
scur.execute("SELECT event_id,hw,aw,m,minute,sel,ltp FROM bf_hist_price WHERE ht_offset IS NOT NULL AND mkt='OU15' AND sel='OVER' ORDER BY event_id,m")
def process(rs):
    global n_ev,n_seen
    n_seen+=1
    hw,aw=norm(rs[0][1]),norm(rs[0][2]); d=rs[0][3].date()
    rec=G.get((d,hw,aw)) or G.get((d-datetime.timedelta(days=1),hw,aw)) or G.get((d+datetime.timedelta(days=1),hw,aw))
    if n_seen==300:
        print(f"SELF-CHECK after 300 events: {n_ev} joined",flush=True)
        if n_ev<30: sys.exit("ABORT join")
    if not rec: return
    n_ev+=1; goals,tot,lg,ph=rec
    px={int(r[4]):float(r[6]) for r in rs if r[6] and r[6]>1.0}
    season='2024/25' if d<datetime.date(2025,7,1) else '2025/26'
    first=goals[0] if goals else 999
    for band,(lo,hi) in (('05-19',(5,19)),('20-34',(20,34)),('35-44',(35,44))):
        for t in range(lo,hi+1,5):
            if first<=t: break
            p=px.get(t)
            if not p or p<1.2 or p>8: continue
            won=tot>1.5
            pnl=((p*(1-SPREAD)-1)*(1-COMM)) if won else -1.0
            rows.append((season,band,t,lg,'tier1' if lg in TOP else 'tier2',ph,p,won,pnl,d))
            break
buf=[]; last=None
for r in scur:
    if last is not None and r[0]!=last: process(buf); buf=[]
    buf.append(r); last=r[0]
if buf: process(buf)
D=pd.DataFrame(rows,columns=['season','band','t','league','tier','home_px','price','won','pnl','date'])
print(f"events seen {n_seen}, joined {n_ev}, candidate trades {len(D)}")
D['fav']=np.where(D.home_px<1.6,'home<1.6',np.where(D.home_px<2.2,'home1.6-2.2',np.where(D.home_px<3.0,'even','away_fav')))
D['pxb']=pd.cut(D.price,[1.2,1.4,1.6,1.8,2.0,2.5,8])
D['month']=pd.to_datetime(D.date).dt.to_period('M').astype(str)
pd.set_option('display.width',250); pd.set_option('display.max_rows',500)
def show(df,by,title,min_n=40):
    T=df.groupby(by+['season'],observed=True).pnl.agg(['size','mean']).unstack('season')
    if T.empty: print(title,"(empty)"); return
    T.columns=[f"{a}_{b}" for a,b in T.columns]
    for c in [c for c in T.columns if c.startswith('mean')]: T[c]=(100*T[c]).round(1)
    T=T[(T.filter(like='size').min(axis=1)>=min_n)]
    print(f"\n{title}  (P&L per £100 backed, held to FT; both seasons)"); print(T.to_string())
R=D[(D.band=='20-34')&(D.tier=='tier1')&(D.fav.isin(['home<1.6','home1.6-2.2']))]
print("\n=== THE RULE: back Over 1.5, 0-0 at 20-34, tier1, home fav <2.2 ===")
print(R.groupby('season').pnl.agg(['size','mean']).assign(mean=lambda x:(100*x['mean']).round(1), win=R.groupby('season').won.mean().round(3)).to_string())
show(R,['league'],'by league'); show(R,['t'],'by entry minute'); show(R,['pxb'],'by Over 1.5 price band'); show(R,['fav'],'by home price band'); show(R,['month'],'by month',min_n=15)
print("\n=== SAME RULE, other segments (sanity: does it generalise or is tier1/home-fav a lucky cell?) ===")
show(D[D.band=='20-34'],['tier','fav'],'20-34 by tier x favourite')
show(D[D.band=='05-19'],['tier','fav'],'05-19 by tier x favourite')
show(D[D.band=='35-44'],['tier','fav'],'35-44 by tier x favourite')
print("\n=== Drawdown of THE RULE, 2025/26, in order, £100 flat stakes ===")
r=R[R.season=='2025/26'].sort_values('date'); c=(100*r.pnl).cumsum(); print(f"trades {len(r)} final £{c.iloc[-1]:.0f} max drawdown £{(c-c.cummax()).min():.0f} worst month {r.groupby('month').pnl.sum().mul(100).min():.0f}")
print("\nVERDICT needs: positive in every tier1 league or at least 4 of 5; no single price band or month carrying it; 05-19 same sign.")
PYFILE
python3 ou15_robust.py
