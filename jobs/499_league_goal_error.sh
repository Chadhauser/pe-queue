#!/bin/bash
set -o pipefail
# 499_league_goal_error (Finder 2026-11-04, queue item 52): DOES A LEAGUE'S GOAL ERROR IN 2024 PREDICT ITS ERROR IN 2025? af_price_map x bf_hist_price x af_fixtures. Entry and guards as jobs/499_segunda_low_goal.sh. The number 499 is reused with a new slug: 450-499 are all taken.
# ENTRY: earliest real OU25 print in tape minutes 0..2, both UNDER and OVER (ltp >= 1.01). Lag outside -5..+20 min v the af kick-off = dropped, counted. A goal with af minute strictly before the print minute = dropped; same minute stays.
# ERROR: per league and season, mean(Under won) - mean(p), in points, p = (1/u)/(1/u+1/o), overround removed. Negative = Under won less often than priced. Leagues with n >= 100 in BOTH seasons enter the rank correlation; a league under n 100 in 2024 is never traded.
# CHOSEN ON 2024 ONLY: error <= -2 points: LAY Under 2.5 in 2025; error >= +2 points: BACK it. One bet per game, at the Under first print, one tick adverse, 2% commission, £10 risk, hold to settle. Cuts of 1 and 3 points shown too. A single season cannot meet the two-half rule by season, so halves are the two sides of the 2025 median date.
# x3 = three ticks adverse. LTP only, so a pass is an upper bound. Reverse check: choose on 2025, trade 2024.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
from scipy.stats import spearmanr
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
pd.set_option('display.width',240); pd.set_option('display.max_rows',200); pd.set_option('display.max_columns',40)
T0=time.time()
LAD=[]
for lo,hi,st in ((1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)):
    x=lo
    while x<hi-1e-9: LAD.append(round(x,2)); x+=st
LAD.append(1000.0); LADA=np.array(LAD)
def pos(p): return int(np.searchsorted(LADA,round(float(p),2)-1e-9))
def up(p,k=1): return float(LADA[min(pos(p)+k,len(LADA)-1)])
def dn(p,k=1): return float(LADA[max(pos(p)-k,0)])
def net(x): return x*0.98 if x>0 else x
def lay_u(p,under,k=1): return -10.0 if under else net(10/(up(p,k)-1))
def back_u(p,under,k=1):
    a=dn(p,k)
    return None if a<=1.01 else (net(10*(a-1)) if under else -10.0)
def p_under(u,o): return (1/u)/(1/u+1/o)
def side_for(err,cut): return 'LAY' if err<=-cut else 'BACK' if err>=cut else None
def tstat(v):
    v=np.asarray(v,dtype=float); n=len(v)
    if n<2: return 0.0
    s=v.std(ddof=1); return float(v.mean()/(s/np.sqrt(n))) if s>0 else 0.0
# known answers, worked by hand
assert up(2.0)==2.02 and dn(2.0)==1.99 and up(2.0,3)==2.06
assert lay_u(2.0,True)==-10.0 and abs(lay_u(2.0,False)-10/1.02*0.98)<1e-9 and abs(back_u(2.0,True)-9.702)<1e-9 and back_u(2.0,False)==-10.0 and back_u(1.02,True) is None
assert abs(p_under(2.0,2.0)-0.5)<1e-12 and abs(p_under(1.5,3.0)-2/3)<1e-12
assert side_for(-2.0,2)=='LAY' and side_for(2.0,2)=='BACK' and side_for(-1.99,2) is None and side_for(0,2) is None
assert abs(spearmanr([1,2,3,4],[1,2,3,4])[0]-1)<1e-9 and abs(spearmanr([1,2,3,4],[4,3,2,1])[0]+1)<1e-9 and abs(tstat([1,3])-2.0)<1e-9
print("known-answer checks: OK",flush=True)
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
G=pd.read_sql("""SELECT m.event_id,f.fixture_id,f.league_id,f.league,f.season,f.kickoff,f.hg,f.ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL AND f.season IN (2024,2025)""",con)
EV=pd.read_sql("SELECT fixture_id,min(coalesce(minute,0)) gm FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal') AND coalesce(minute,0)<=2 GROUP BY 1",con,params=(list(map(int,G.fixture_id)),))
first_goal=dict(zip(EV.fixture_id,EV.gm)); parts=[]
for i in range(0,len(G),1000):
    P=pd.read_sql("SELECT event_id,sel,minute,m,ltp::float ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt='OU25' AND sel IN ('UNDER','OVER') AND minute>=0 AND minute<=2 AND ltp>=1.01 AND ltp<1000",con,params=(list(G.event_id.iloc[i:i+1000]),))
    parts.append(P.sort_values(['event_id','sel','minute','m']).drop_duplicates(['event_id','sel']))
    print(f"  {min(i+1000,len(G))}/{len(G)} {time.time()-T0:.0f}s",flush=True)
P=pd.concat(parts,ignore_index=True).merge(G,on='event_id'); n0=P.event_id.nunique()
P['lag']=(pd.to_datetime(P.m,utc=True)-pd.to_datetime(P.kickoff,utc=True)).dt.total_seconds()/60
bad=(P.lag<-5)|(P.lag>20); gm=P.fixture_id.map(first_goal); kn=gm.notna()&(gm<P.minute)
print(f"games with a print {n0}; rows dropped, lag {int(bad.sum())}, goal known before the print {int(kn.sum())}",flush=True); P=P[~bad&~kn]
Q=P.pivot_table(index=['event_id','league_id','league','season','kickoff','hg','ag'],columns='sel',values='ltp').reset_index().dropna(subset=['UNDER','OVER'])
Q['p']=p_under(Q.UNDER,Q.OVER); Q['under']=(Q.hg+Q.ag<2.5).astype(float); Q['ko']=pd.to_datetime(Q.kickoff,utc=True)
assert not Q.event_id.duplicated().any(); print(f"games with both sides printed: {len(Q)} {Q.groupby('season').size().to_dict()}",flush=True)
L=Q.groupby(['league','season']).agg(n=('p','size'),won=('under','mean'),imp=('p','mean')).reset_index(); L['err']=100*(L.won-L.imp); W=L.pivot(index='league',columns='season',values=['n','err'])
W.columns=[f'{a}{b}' for a,b in W.columns]; W=W.dropna(); B=W[(W.n2024>=100)&(W.n2025>=100)].copy()
r,pv=spearmanr(B.err2024,B.err2025); rng=np.random.default_rng(0); perm=[spearmanr(B.err2024,rng.permutation(B.err2025.values))[0] for _ in range(5000)]
print("\n== LEAGUE ERROR, points, Under 2.5 won minus priced\n",W.round(2).sort_values('err2024').to_string())
print(f"\n== RANK CORRELATION 2024 v 2025: rho {r:.3f}, p {pv:.4f}, permutation two-sided p {np.mean(np.abs(perm)>=abs(r)):.4f}, leagues {len(B)}; pearson {np.corrcoef(B.err2024,B.err2025)[0,1]:.3f}; job 489 had rho 0.55, 17 leagues",flush=True)
def trade(fit,test,cut,lab):
    e=L[(L.season==fit)&(L.n>=100)].set_index('league').err; rows=[]
    for g in Q[Q.season==test].itertuples():
        if g.league not in e.index: continue
        s=side_for(e[g.league],cut)
        if s is None: continue
        u=bool(g.under); a=lay_u(g.UNDER,u) if s=='LAY' else back_u(g.UNDER,u); a3=lay_u(g.UNDER,u,3) if s=='LAY' else back_u(g.UNDER,u,3)
        if a is None or a3 is None: continue
        rows.append(dict(league=g.league,side=s,ko=g.ko,x=a,x3=a3,px=g.UNDER))
    D=pd.DataFrame(rows); out=[]
    if D.empty: return D,out
    med=D.ko.sort_values().iloc[len(D)//2]
    for nm,d in [('ALL',D)]+[(f'side {k}',x) for k,x in D.groupby('side')]:
        a=d[d.ko<med].x; b=d[d.ko>=med].x; v=d.x
        o=dict(run=lab,cut=cut,line=nm,leagues=d.league.nunique(),n=len(v),per10=v.mean(),t=tstat(v),n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,x3=d.x3.mean(),px=d.px.median(),best=v.max())
        o['PASS']=bool(o['n']>=300 and o['n1']>=150 and o['n2']>=150 and o['t']>=3.5 and o['h1']>0 and o['h2']>0 and o['per10']>=0.15); out.append(o)
    return D,out
O=[]; K={}
for cut in (1,2,3):
    D,o=trade(2024,2025,cut,'fit 2024, trade 2025'); O+=o; K[cut]=D
    D,o=trade(2025,2024,cut,'reverse: fit 2025, trade 2024'); O+=o
R=pd.DataFrame(O); print("\n== TRADES, one bet per game\n",R.drop(columns=['PASS']).round(3).to_string(index=False))
print("\n== by league, fit 2024, cut 2, trade 2025\n",K[2].groupby(['side','league']).x.agg(['size','mean',tstat]).round(3).to_string())
C=Q[Q.season==2025]; print(f"\ncontrols, every 2025 game: lay Under {np.mean([lay_u(p,bool(u)) for p,u in zip(C.UNDER,C.under)]):+.3f}, back Under {np.mean([x for x in (back_u(p,bool(u)) for p,u in zip(C.UNDER,C.under)) if x is not None]):+.3f}, n {len(C)}")
W2=R[R.PASS&(R.run.str.startswith('fit'))]; print(f"\n== SURVIVORS: {len(W2)} (2025 only, chosen on 2024, LTP-based so an upper bound)"); print(W2.round(3).to_string(index=False) if len(W2) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
