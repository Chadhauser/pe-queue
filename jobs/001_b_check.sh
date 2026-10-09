#!/bin/bash
# 001: corrected B/C strategy check (settled goals, fresh prices)
cd /root/pe-scan && cat > strategy_check_v3.py <<'PYFILE'
"""
Poisson in-play gap scan v2 — Peter, 8 Oct 2026. Replaces the stale-price-contaminated v1.
Our own fair price at every minute vs Betfair, on the two-season Basic tape.
FIXES vs v1: (1) a price is used at minute t only if it TRADED at minute t (bf_hist_price has a row
only for minutes with an update, so a missing minute = no trade = stale); (2) nothing is used in the
3 minutes after a goal; (3) exits also require a fresh (traded) price; (4) 2 pct spread each way
on LTP, 2 pct commission; (5) one trade per event per selection per score state.
Model: two Poisson rates fitted at kick-off to the first in-play MO + OU2.5 prices; remaining
scoring falls with the clock, late factor 0.3 (as calibrated 6 Oct). Goals from fts_advanced_results.
Train 2024/25, hold 2025/26.
"""
import sys, re, math, datetime, collections
import numpy as np, psycopg2
from scipy.optimize import minimize
from scipy.stats import poisson
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
LATE=0.3; HOLD=10; GOAL_GAP=3; SPREAD=0.02; COMM=0.02; THRESH=[0.03,0.05,0.08,0.12]; MAXG=8

def norm(s): return re.sub(r'[^a-z]','',(s or '').lower().split(' ')[0])
con=psycopg2.connect(DB,sslmode='require')
cur=con.cursor()
cur.execute("SELECT match_date, home_team, away_team, goal_times FROM fts_advanced_results WHERE match_date>='2024-08-01'")
G={}
for d,h,a,gt in cur.fetchall():
    d=datetime.date.fromisoformat(str(d)[:10])
    goals=[]
    for t in (gt or '').split('|'):
        mm=re.match(r"\s*(\d+)(?:\+(\d+))?\((H|A)\)",t)
        if mm: goals.append((int(mm.group(1))+int(mm.group(2) or 0),mm.group(3)))
    G[(d,norm(h),norm(a))]=sorted(goals)
print("goal records",len(G),flush=True)

def remaining(t): f=max(0.0,1-t/90.0); return f*(1+LATE*t/90.0)
def probs(lh,la):
    ph=poisson.pmf(np.arange(MAXG),lh); pa=poisson.pmf(np.arange(MAXG),la); M=np.outer(ph,pa)
    H=np.tril(M,-1).sum(); A=np.triu(M,1).sum(); D=np.trace(M)
    tot=np.add.outer(np.arange(MAXG),np.arange(MAXG)); O25=M[tot>2.5].sum()
    return H,D,A,O25
def fit(mo,o25):
    # mo = implied normalised (H,D,A); o25 = implied P(over 2.5) normalised
    def loss(x):
        lh,la=math.exp(x[0]),math.exp(x[1]); H,D,A,O=probs(lh,la)
        return (H-mo[0])**2+(D-mo[1])**2+(A-mo[2])**2+(0 if o25 is None else (O-o25)**2)
    r=minimize(loss,[math.log(1.4),math.log(1.1)],method='Nelder-Mead',options={'xatol':1e-4,'fatol':1e-8,'maxiter':400})
    return math.exp(r.x[0]),math.exp(r.x[1]),r.fun
def fair(lh,la,t,sh,sa):
    f=remaining(t); ph=poisson.pmf(np.arange(MAXG),lh*f); pa=poisson.pmf(np.arange(MAXG),la*f); M=np.outer(ph,pa)
    i,j=np.indices(M.shape); gh=sh+i; ga=sa+j
    return {'HOME':M[gh>ga].sum(),'DRAW':M[gh==ga].sum(),'AWAY':M[gh<ga].sum(),'OVER':M[(gh+ga)>2.5].sum(),'UNDER':M[(gh+ga)<2.5].sum()}


trades=[]; n_ev=0; n_seen=0; dropped=[0]
STRATS={
 'B  back OVER, away leads 1-0, 30-54, hold15': dict(mkt='OU25',sel='OVER',tmin=30,tmax=54,hold=15,cond=lambda sh,sa:(sh,sa)==(0,1)),
 'Bh back OVER, home leads 1-0, 30-54, hold15': dict(mkt='OU25',sel='OVER',tmin=30,tmax=54,hold=15,cond=lambda sh,sa:(sh,sa)==(1,0)),
 'C  back DRAW, 0-0, 55-80, hold20':            dict(mkt='MO',  sel='DRAW',tmin=55,tmax=80,hold=20,cond=lambda sh,sa:(sh,sa)==(0,0)),
 'B2 back OVER, away leads 1-0, 30-54, hold15, +12pct target': dict(mkt='OU25',sel='OVER',tmin=30,tmax=54,hold=15,cond=lambda sh,sa:(sh,sa)==(0,1),target=0.12),
}
scur=con.cursor(name='tape'); scur.itersize=50000
scur.execute("SELECT event_id,event_name,hw,aw,m,minute,mkt,sel,ltp FROM bf_hist_price WHERE ht_offset IS NOT NULL ORDER BY event_id,m")
def process(eid,rows):
    global n_ev,n_seen
    n_seen+=1
    hw,aw=norm(rows[0][2]),norm(rows[0][3]); d=rows[0][4].date()
    goals=G.get((d,hw,aw)) or G.get((d-datetime.timedelta(days=1),hw,aw)) or G.get((d+datetime.timedelta(days=1),hw,aw))
    if n_seen==300:
        print(f"SELF-CHECK after 300 events: {n_ev} joined, {len(trades)} trades",flush=True)
        if n_ev<30: sys.exit("ABORT: join failing")
    if goals is None: return
    n_ev+=1
    px=collections.defaultdict(dict)
    for _,_,_,_,m,minute,mkt,sel,ltp in rows:
        if ltp and ltp>1.0: px[(mkt,sel)][minute]=float(ltp)
    season=2024 if d<datetime.date(2025,7,1) else 2025
    def score(t): return sum(1 for g,s in goals if g<=t and s=='H'),sum(1 for g,s in goals if g<=t and s=='A')
    def near_goal(t): return any(0<=t-g<GOAL_GAP for g,_ in goals)
    for name,S in STRATS.items():
        series=px.get((S['mkt'],S['sel']),{})
        for t in range(S['tmin'],S['tmax']+1):
            if near_goal(t): continue
            sh,sa=score(t)
            if not S['cond'](sh,sa): continue
            if t not in series: continue
            e=series[t]; H=S['hold']
            nxt=[g for g,_ in goals if t<g<=t+H]
            ex=None; how='clock'
            # settled by goals inside the hold?
            if S['mkt']=='OU25':
                tot=sh+sa
                for g,_ in goals:
                    if t<g<=t+H:
                        tot+=1
                        if tot>=3: ex=(g,1.01 if S['sel']=='OVER' else 1000.0); how='settled'; break
            # profit target: first fresh minute where price has fallen enough
            if ex is None and S.get('target'):
                for u in range(t+1,t+H+1):
                    if near_goal(u): continue
                    if u in series and e/series[u]-1>=S['target']: ex=(u,series[u]); how='target'; break
            if ex is None:
                te=(nxt[0]+GOAL_GAP) if nxt else t+H
                for u in range(te,min(te+6,95)):
                    if u in series and not near_goal(u): ex=(u,series[u]); how='goal+3' if nxt else 'clock'; break
            if ex is None:
                if t+H>=90:
                    fh,fa=score(200); won={'DRAW':fh==fa,'OVER':fh+fa>2.5}[S['sel']]; ex=(90,1.01 if won else 1000.0); how='FT'
                else: dropped[0]+=1; break
            bk=e*(1-SPREAD); ly=min(ex[1]*(1+SPREAD),1000); pnl=bk/ly-1
            if pnl>0: pnl*=(1-COMM)
            trades.append((name,season,t,e,ex[1],ex[0],how,bool(nxt),pnl))
            break   # one trade per strategy per match
buf=[]; last=None
for r in scur:
    if last is not None and r[0]!=last:
        process(last,buf); buf=[]
        if n_ev%2000==0 and n_ev: print("events",n_ev,"trades",len(trades),flush=True)
    buf.append(r); last=r[0]
if buf: process(last,buf)
print(f"\nevents joined {n_ev}, trades {len(trades)}, dropped (no fresh exit, not settled) {dropped[0]}",flush=True)
import pandas as pd
T=pd.DataFrame(trades,columns=['strat','season','t','entry','exit','t_exit','how','goal_in_hold','pnl'])
T.to_csv('/root/pe-scan/strategy_check_v3_trades.csv',index=False)
def ts(x): return x.mean()/(x.std(ddof=1)/math.sqrt(len(x))) if len(x)>2 and x.std()>0 else 0
print("\nSTRATEGY CHECK v3 — settled goals counted, fresh prices only, 2pct spread each way, 2pct comm")
for name,g in T.groupby('strat'):
    print(f"\n{name}")
    for yr in (2024,2025):
        x=g[g.season==yr]
        if len(x)==0: continue
        c=x.pnl.cumsum(); dd=(c-c.cummax()).min()
        print(f"  {yr}: n={len(x):5d} ROI={100*x.pnl.mean():+6.1f}% t={ts(x.pnl):5.1f} win%={100*(x.pnl>0).mean():4.1f} total={c.iloc[-1]:+7.1f}u maxDD={dd:6.1f}u | exits: "+", ".join(f"{k} {v}" for k,v in x.how.value_counts().items()))
    print("  by exit type (both seasons): "+" | ".join(f"{k}: n={len(v)} ROI={100*v.pnl.mean():+.1f}%" for k,v in g.groupby('how')))
    print("  by entry price: "+" | ".join(f"{str(k)}: n={len(v)} ROI={100*v.pnl.mean():+.1f}%" for k,v in g.groupby(pd.cut(g.entry,[1,1.3,1.6,2.0,2.5,4,10]),observed=True)))
PYFILE
python3 strategy_check_v3.py
