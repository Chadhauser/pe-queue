#!/bin/bash
# 040 (= 037 rerun, formatting crash fixed): THE GOAL SIGNAL SCORED AGAINST THE MARKET — the test it never had. goal_live_predictions holds every live call the engine
# made since July (1.75M rows, 29,874 fixtures, signal_direction + alert flag, settled with the real next-goal minute). bf_price_log
# holds our own live Betfair tape since 22 Aug (best back/lay every 60s in-play). Join by teams + time and ask:
#   (A) Calibration: engine p_goal_next_10 vs the market's implied next-10-min goal probability (from the Over 2.5 price, Poisson).
#       Who is better calibrated, out of sample, on the same moments?
#   (B) Money: every ALERT the engine sent, traded at the live price at that moment (BACK at best back, LAY at best lay), exit at the
#       next goal +3 min or +10 min, 2pct comm. P&L per £100 by direction. This is "the goal signal says bet" turned into pounds.
cd /root/pe-scan && cat > goal_signal_vs_market_v2.py <<'PYFILE'
import re, sys, math, datetime, collections, psycopg2, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
COMM=0.02
con=psycopg2.connect(DB,sslmode='require')
P=pd.read_sql("""SELECT p.id, p.captured_at, p.minute, p.score_home, p.score_away, p.p_goal_next_10, p.p_goal_next_15, p.signal_direction, p.alert_sent,
   p.goal_within_10, p.next_goal_minute, w.home_team, w.away_team, w.league FROM goal_live_predictions p JOIN goal_signal_watchlist w ON w.id=p.watchlist_id
   WHERE p.captured_at >= '2026-08-22' AND p.settled AND p.minute BETWEEN 10 AND 80""",con)
print("predictions since tape start:",len(P),"fixtures",P[['home_team','away_team','captured_at']].drop_duplicates(['home_team','away_team']).shape[0],"alerts",int(P.alert_sent.sum()),flush=True)
ALIAS={'manchester city':'man city','manchester united':'man utd','nottingham forest':'nottm forest','wolverhampton wanderers':'wolves','sheffield united':'sheff utd','paris saint germain':'psg',
 'borussia dortmund':'dortmund','borussia monchengladbach':'mgladbach','bayer leverkusen':'leverkusen','rb leipzig':'rb leipzig','fc koln':'koln','ac milan':'milan','hellas verona':'verona','athletic club':'athletic bilbao','real betis':'betis',
 'vfb stuttgart':'stuttgart','vfl wolfsburg':'wolfsburg','vfl bochum':'bochum','1899 hoffenheim':'hoffenheim','sc freiburg':'freiburg','fc augsburg':'augsburg','werder bremen':'werder bremen','1. fc heidenheim':'heidenheim','union berlin':'union berlin','fsv mainz 05':'mainz',
 'west ham united':'west ham','newcastle united':'newcastle','tottenham hotspur':'tottenham','leeds united':'leeds','brighton & hove albion':'brighton','leicester city':'leicester','norwich city':'norwich','swansea city':'swansea','cardiff city':'cardiff','stoke city':'stoke','hull city':'hull','derby county':'derby','birmingham city':'birmingham','coventry city':'coventry','bristol city':'bristol city','preston north end':'preston','queens park rangers':'qpr','sheffield wednesday':'sheff wed','west bromwich albion':'west brom','blackburn rovers':'blackburn','ipswich town':'ipswich','luton town':'luton','plymouth argyle':'plymouth','oxford united':'oxford utd','portsmouth':'portsmouth','millwall':'millwall','watford':'watford','middlesbrough':'middlesbrough','sunderland':'sunderland','burnley':'burnley'}
def nn(s):
    s=re.sub(r'[^a-z0-9 &.\-]','',(s or '').lower()).strip(); s=ALIAS.get(s,s)
    return re.sub(r'[^a-z]','',s.split(' ')[0])
# tape: parse event from market_name "Home v Away - Over/Under 2.5 Goals"
T=pd.read_sql("""SELECT captured_at, market_name, selection_name, back_price, lay_price FROM bf_price_log
   WHERE captured_at >= '2026-08-22' AND (market_name LIKE '%% - Over/Under 2.5 Goals' OR market_name LIKE '%% - Match Odds')
   AND (selection_name IN ('Over 2.5 Goals','Under 2.5 Goals','The Draw'))""",con)
print("tape rows",len(T),flush=True)
T['event']=T.market_name.str.split(' - ').str[0]
ev=T.event.str.split(' v ',n=1,expand=True); T['hk']=ev[0].map(nn); T['ak']=ev[1].map(nn)
T['key']=T.hk+'|'+T.ak
T=T.sort_values('captured_at')
TK={k:g for k,g in T.groupby(['key','selection_name'])}
P['key']=P.home_team.map(nn)+'|'+P.away_team.map(nn)
print("prediction keys matching a tape key:",round(float(P.key.isin(set(T.key)).mean()),3),flush=True)
def px_at(key,sel,when,tol_s=120):
    g=TK.get((key,sel))
    if g is None: return None
    i=g.captured_at.searchsorted(when)
    cands=[]
    if i<len(g): cands.append(g.iloc[i])
    if i>0: cands.append(g.iloc[i-1])
    best=None
    for r in cands:
        dt=abs((r.captured_at-when).total_seconds())
        if dt<=tol_s and (best is None or dt<best[0]): best=(dt,r)
    return None if best is None else best[1]
rows=[]
A=P[P.alert_sent & P.signal_direction.isin(['LAY_THE_DRAW','LAY_DRAW','BACK_OVER','BACK_UNDER','BACK_DRAW'])].copy()
print("alerts to price:",len(A),flush=True)
for r in A.itertuples():
    d=r.signal_direction
    sel={'LAY_THE_DRAW':'The Draw','LAY_DRAW':'The Draw','BACK_DRAW':'The Draw','BACK_OVER':'Over 2.5 Goals','BACK_UNDER':'Under 2.5 Goals'}[d]
    side='lay' if d.startswith('LAY') else 'back'
    e=px_at(r.key,sel,r.captured_at)
    if e is None: continue
    goal_in=(r.next_goal_minute is not None and not pd.isna(r.next_goal_minute) and 0<r.next_goal_minute-r.minute<=10)
    exit_when=r.captured_at+pd.Timedelta(minutes=(int(r.next_goal_minute-r.minute)+3) if goal_in else 10)
    x=px_at(r.key,sel,exit_when,tol_s=180)
    if x is None: continue
    if side=='back':
        ent=float(e.back_price); ext=float(x.lay_price) if x.lay_price else None
        if not ent or not ext: continue
        pnl=ent/ext-1
    else:
        ent=float(e.lay_price); ext=float(x.back_price) if x.back_price else None
        if not ent or not ext: continue
        pnl=1-ent/ext
    pnl=pnl*(1-COMM) if pnl>0 else pnl
    rows.append((r.captured_at.date(),d,r.league,r.minute,r.p_goal_next_10,ent,ext,goal_in,pnl))
D=pd.DataFrame(rows,columns=['d','direction','league','minute','p10','entry','exit','goal_in_10','pnl'])
pd.set_option('display.width',250)
print(f"\n=== B. MONEY: {len(D)} alerts priced at the live market (of {len(A)} sent) ===")
print(D.groupby('direction').pnl.agg(['size','mean']).assign(mean=lambda x:(100*x['mean']).round(1), goal10=D.groupby('direction').goal_in_10.mean().round(3)).to_string())
D['month']=pd.to_datetime(D.d).dt.to_period('M').astype(str)
print("\nby month:"); print(D.groupby(['month','direction']).pnl.agg(['size','mean']).assign(mean=lambda x:(100*x['mean']).round(1)).to_string())
print(f"\nTOTAL at £10 a trade: £{(10*D.pnl.sum()):.0f} over {len(D)} alerts")
# ---- A. calibration vs market on ALL moments with a priced Over 2.5 (sample for speed)
S=P[P.p_goal_next_10.notna()].sample(min(60000,len(P)),random_state=1)
out=[]
for r in S.itertuples():
    e=px_at(r.key,'Over 2.5 Goals',r.captured_at,tol_s=90)
    if e is None or not e.back_price or not e.lay_price: continue
    p_over=2/(float(e.back_price)+float(e.lay_price))  # mid implied, overround-light
    goals=int(r.score_home or 0)+int(r.score_away or 0); rem=max(90-r.minute,1)
    # market-implied goal rate: P(total>2.5 | goals so far) under Poisson with remaining rate L: solve L from p_over, then P(goal in 10)=1-exp(-L*10/rem)
    need=max(3-goals,0)
    if need==0: continue
    lo,hi=0.0,8.0
    for _ in range(40):
        L=(lo+hi)/2; pm=1-sum(math.exp(-L)*L**k/math.factorial(k) for k in range(need))
        lo,hi=(L,hi) if pm<p_over else (lo,L)
    L=(lo+hi)/2; p_mkt=1-math.exp(-L*10/rem)
    out.append((r.p_goal_next_10,p_mkt,bool(r.goal_within_10)))
C=pd.DataFrame(out,columns=['p_engine','p_market','y'])
def ll(p,y): p=np.clip(p,1e-3,1-1e-3); return float(-(y*np.log(p)+(1-y)*np.log(1-p)).mean())
def brier(p,y): return float(((p-y)**2).mean())
print(f"\n=== A. CALIBRATION on {len(C)} live moments (same moments, same outcomes) ===")
print(f"engine  : log-loss {ll(C.p_engine,C.y):.4f}  brier {brier(C.p_engine,C.y):.4f}  mean p {C.p_engine.mean():.3f}")
print(f"market  : log-loss {ll(C.p_market,C.y):.4f}  brier {brier(C.p_market,C.y):.4f}  mean p {C.p_market.mean():.3f}")
print(f"actual goal-in-10 rate: {C.y.mean():.3f}")
C['eb']=pd.cut(C.p_engine,[0,.2,.3,.4,.5,.6,1]); C['mb']=pd.cut(C.p_market,[0,.2,.3,.4,.5,.6,1])
print("\nengine buckets -> actual:"); print(C.groupby('eb',observed=True).y.agg(['size','mean']).round(3).to_string())
print("market buckets -> actual:"); print(C.groupby('mb',observed=True).y.agg(['size','mean']).round(3).to_string())
print("\nDISAGREEMENT: where engine says 10+ pts MORE likely than market, actual rate vs both:")
dis=C[C.p_engine-C.p_market>=0.10]; print(f"n {len(dis)} engine {dis.p_engine.mean():.3f} market {dis.p_market.mean():.3f} actual {dis.y.mean():.3f}")
dis=C[C.p_market-C.p_engine>=0.10]; print(f"engine 10+ pts LESS: n {len(dis)} engine {dis.p_engine.mean():.3f} market {dis.p_market.mean():.3f} actual {dis.y.mean():.3f}")
print("\nREADING: lower log-loss = better. If the engine is better where it disagrees with the market, there is an edge to trade; if the market is, the engine adds nothing the price lacks.")
PYFILE
python3 goal_signal_vs_market_v2.py
