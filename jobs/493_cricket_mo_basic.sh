#!/bin/bash
set -o pipefail
# 493 (Finder 2026-11-04, queue item 42): CRICKET MATCH ODDS IN-PLAY on bf_hist_other (Betfair BASIC, Sep 2024..Sep 2026). Census, then price-band and momentum grids.
# DATA LIMIT: BASIC is about one LTP print a minute, with no book. A real fill may be worse than a print, so any pass is an upper bound and needs a real touch before any stake.
# STATES, one entry per runner per market per state: FIRST = first in-play print of the market. E30/E60/E120/E240 = minutes since that print; a market with no print after that time gets no trade. P25/P50/P75 = 25/50/75% of the market's in-play prints, as the item asks.
# P25/P50/P75 LOOK AHEAD: where those points fall depends on the total prints, known only when the match has ended, so they are shown but can NEVER pass. E30..E240 are the honest versions.
# ENTRY: the runner's first print strictly after the state time, one tick adverse. Never the state's own print. Back at 1.01 cannot be filled: counted.
# MOMENTUM (item 9's test): first print per market where a runner is at least 15% shorter than 20 of its own prints earlier. Enter at its next print, back and lay. M15X20 exits 20 prints later at a real print, one tick adverse; if the market has no such print, settled at the result, never dropped. M15SET holds to the result.
# RESULT: inferred from the runners' final in-play prints. One runner <= 1.05 = it won, the rest lost. Two <= 1.05 = conflict, all unknown. None: a runner >= 100 lost, the rest unknown. Unknown = -£10 on BOTH sides. KNOWN mean is a diagnostic only; no other result source covers cricket on this box.
# COST: 2% commission on profit, £10 stake / £10 liability. Halves: median market date. t per trade, t_c clustered by market.
# LAYS BELOW 1.10 win many times the liability on a stale print, so x110 = mean without entries under 1.10, and a pass needs x110 >= +£0.15 as well. max_win = largest single trade.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,time,random,warnings,psycopg2,pandas as pd,numpy as np
from collections import Counter
warnings.filterwarnings('ignore')
pd.set_option('display.width',230); pd.set_option('display.max_rows',120); pd.set_option('display.max_columns',30)
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
BUDGET=1500; CHUNK=400
LAD=[]
for lo,hi,st in ((1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)):
    x=lo
    while x<hi-1e-9: LAD.append(round(x,2)); x+=st
LAD.append(1000.0); LAD=np.array(LAD)
def pos(p): return int(np.searchsorted(LAD,round(float(p),2)-1e-9))
def dn(p): return float(LAD[max(pos(p)-1,0)])
def up(p): return float(LAD[min(pos(p)+1,len(LAD)-1)])
def comm(r): return r*0.98 if r>0 else r
def back_settle(p,won):
    a=dn(p)
    if a<=1.01: return None
    return -10.0 if won is None else comm(10*(a-1) if won else -10.0)
def lay_settle(p,won):
    a=up(p)
    return -10.0 if won is None else comm(-10.0 if won else 10/(a-1))
def back_scalp(p,q):
    a=dn(p)
    if a<=1.01: return None
    return comm(10*(a/up(q)-1))
def lay_scalp(p,q):
    a=up(p); return comm(10/(a-1)*(1-a/dn(q)))
def result_of(fin):
    """fin: runner -> final in-play print. Returns (runner -> True/False/None, conflict flag)."""
    w=[s for s,p in fin.items() if p<=1.05]
    if len(w)==1: return {s:s==w[0] for s in fin},False
    if len(w)>1: return {s:None for s in fin},True
    return {s:(False if p>=100 else None) for s,p in fin.items()},False
def next_idx(ts,t):
    """Index of the first print strictly after t, or None."""
    i=int(np.searchsorted(ts,t,'right'))
    return i if i<len(ts) else None
def mom_first(p,k=20,x=0.15):
    """First index i>=k with p[i] at least x shorter than p[i-k], or None."""
    for i in range(k,len(p)):
        if p[i]<=p[i-k]*(1-x)+1e-9: return i
    return None
def band(p):
    for hi,lab in ((1.1,'<1.1'),(1.25,'1.1-1.25'),(1.5,'1.25-1.5'),(2,'1.5-2'),(3,'2-3'),(5,'3-5'),(10,'5-10'),(25,'10-25')):
        if p<hi: return lab
    return '25+'
def tstat(v):
    v=np.asarray(v,dtype=float)
    return float(v.mean()/(v.std(ddof=1)/np.sqrt(len(v)))) if len(v)>1 and v.std(ddof=1)>0 else 0.0
# known answers, worked by hand
assert dn(2.0)==1.99 and up(2.0)==2.02 and up(1.99)==2.0 and dn(3.0)==2.98 and up(3.0)==3.05
assert abs(back_settle(2.0,True)-9.702)<1e-9 and back_settle(2.0,False)==-10.0 and back_settle(2.0,None)==-10.0 and back_settle(1.02,True) is None   # 10 x 0.99 x 0.98
assert abs(lay_settle(3.0,False)-10/2.05*0.98)<1e-9 and lay_settle(3.0,True)==-10.0 and lay_settle(3.0,None)==-10.0                                  # lay 3.0 fills 3.05
assert abs(back_scalp(2.0,1.8)-0.97459)<1e-4 and back_scalp(1.02,1.5) is None                                                                        # 1.99 v 1.81: 10 x 0.09945 x 0.98
assert abs(lay_scalp(2.0,2.5)-1.78210)<1e-4 and back_scalp(2.0,3.0)<0 and lay_scalp(2.0,1.5)<0                                                       # 2.02 v 2.48, stake 9.804
assert result_of({'A':1.03,'B':40.0})==({'A':True,'B':False},False) and result_of({'A':1.03,'B':1.04})==({'A':None,'B':None},True)
assert result_of({'A':2.0,'B':150.0})==({'A':None,'B':False},False) and result_of({'A':2.0,'B':3.0})==({'A':None,'B':None},False)
assert result_of({'A':1.02,'B':200.0,'The Draw':60.0})==({'A':True,'B':False,'The Draw':False},False) and result_of({'A':1.05,'B':5.0})[0]['A'] is True
T_=np.array([10.,20.,30.])
assert next_idx(T_,10.)==1 and next_idx(T_,5.)==0 and next_idx(T_,30.) is None                                                                       # strictly after: never the state's own print
P_=[5.0]*20+[4.25,3.0]
assert mom_first(P_)==20 and mom_first([5.0]*20+[4.3]) is None and mom_first([5.0]*5) is None                                                        # 5.0 x 0.85 = 4.25: at the level counts
assert band(1.09)=='<1.1' and band(1.1)=='1.1-1.25' and band(2.0)=='2-3' and band(25.0)=='25+' and abs(tstat([1,3])-2.0)<1e-9
print("known-answer checks: OK",flush=True)

con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'; SET max_parallel_workers_per_gather=0")
t0=time.time()
cur.execute("""WITH RECURSIVE t AS ((SELECT market_id FROM bf_hist_other WHERE sport='Cricket' ORDER BY market_id LIMIT 1)
  UNION ALL SELECT (SELECT market_id FROM bf_hist_other WHERE sport='Cricket' AND market_id>t.market_id ORDER BY market_id LIMIT 1) FROM t WHERE t.market_id IS NOT NULL)
  SELECT market_id FROM t WHERE market_id IS NOT NULL""")
ALL=[r[0] for r in cur.fetchall()]; MID=[m for m in ALL if m.startswith('MATCH_ODDS|')]; random.Random(4).shuffle(MID)
print(f"cricket market ids {len(ALL)}, MATCH_ODDS {len(MID)} | {int(time.time()-t0)}s",flush=True)
SK=Counter(); rows=[]; done=0; cen=[]; gaps=[]
STATES={'FIRST':None,'E30':30,'E60':60,'E120':120,'E240':240,'P25':.25,'P50':.5,'P75':.75}
def add(state,side,kind,mk,day,country,sel,p,r,known):
    rows.append((state,side,kind,mk,day,country,sel,p,band(p),known,r))
for c_ in range(0,len(MID),CHUNK):
    if time.time()-t0>BUDGET: SK['chunks not pulled, budget']+=1; break
    ids=MID[c_:c_+CHUNK]
    cur.execute("""SELECT market_id,market_time,country,sel,extract(epoch from ts)::float8,ltp::float8 FROM bf_hist_other
      WHERE sport='Cricket' AND market_id=ANY(%s) AND market_type='MATCH_ODDS' AND inplay AND ltp IS NOT NULL AND ltp>=1.01 AND ltp<=1000""",(ids,))
    d=pd.DataFrame(cur.fetchall(),columns=['mid','mt','country','sel','ts','ltp']); done+=len(ids)
    if d.empty: SK['chunk: no in-play rows']+=1; continue
    d=d.drop_duplicates(['mid','sel','ts']).sort_values(['mid','ts','sel'],kind='stable')
    for mk,g in d.groupby('mid',sort=False):
        day=pd.Timestamp(g.mt.iloc[0]).date(); ct=g.country.iloc[0]
        run={s:(x.ts.values,x.ltp.values) for s,x in g.groupby('sel',sort=False)}
        res,conf=result_of({s:float(v[1][-1]) for s,v in run.items()})
        known=any(v is True for v in res.values()); SK['market']+=1; SK['market: winner inferred']+=known; SK['market: conflict']+=conf
        allt=np.sort(g.ts.values); T0=allt[0]; N=len(allt)
        cen.append((mk,day,ct,len(run),N,(allt[-1]-T0)/60,known))
        for s,(ts,_) in run.items():
            if len(ts)>1: gaps.append(float(np.median(np.diff(ts))))
        for st,v in STATES.items():
            ts_=T0 if st=='FIRST' else (T0+v*60 if st[0]=='E' else allt[int(v*N)])
            for s,(ts,p) in run.items():
                i=next_idx(ts,ts_)
                if i is None: SK[f'{st}: runner has no later print']+=1; continue
                x=float(p[i]); w=res[s]; a=back_settle(x,w); b=lay_settle(x,w)
                if a is None: SK[f'{st}: back unfillable']+=1
                else: add(st,'B','settle',mk,day,ct,s,x,a,w is not None)
                add(st,'L','settle',mk,day,ct,s,x,b,w is not None)
        # momentum: the earliest trigger in the market, one per market
        trig=[]
        for s,(ts,p) in run.items():
            i=mom_first(p)
            if i is not None: trig.append((ts[i],s,i))
        if trig:
            _,s,i=min(trig,key=lambda z:(z[0],z[1])); ts,p=run[s]; w=res[s]
            if i+1>=len(p): SK['momentum: no next print']+=1
            else:
                x=float(p[i+1]); a=back_settle(x,w); b=lay_settle(x,w)
                if a is None: SK['momentum: back unfillable']+=1
                else: add('M15SET','B','settle',mk,day,ct,s,x,a,w is not None)
                add('M15SET','L','settle',mk,day,ct,s,x,b,w is not None)
                if i+21<len(p):
                    q=float(p[i+21]); SK['momentum: exit print']+=1; a2=back_scalp(x,q); b2=lay_scalp(x,q); kn=True
                else: SK['momentum: settled, no exit print']+=1; a2,b2,kn=a,b,w is not None
                if a2 is not None: add('M15X20','B','x20',mk,day,ct,s,x,a2,kn)
                add('M15X20','L','x20',mk,day,ct,s,x,b2,kn)
    print(f"  {done}/{len(MID)} markets | trades {len(rows)} | {int(time.time()-t0)}s",flush=True)
print("coverage:",done,"of",len(MID),"| counts (not hidden):",dict(SK),flush=True)
C=pd.DataFrame(cen,columns=['mk','day','ct','runners','prints','mins','known'])
if C.empty: print("ERROR: no in-play markets, so no verdict"); sys.exit(1)
print(f"\n== CENSUS: markets {len(C)} | {C.day.min()}..{C.day.max()} | winner inferred {C.known.mean():.1%} | prints per market median {C.prints.median():.0f}, p10 {C.prints.quantile(.1):.0f}, p90 {C.prints.quantile(.9):.0f} | in-play minutes median {C.mins.median():.0f} | runner gap between prints median {np.median(gaps):.0f}s")
print("runners per market:",C.runners.value_counts().head(5).to_dict(),"| countries:",C.ct.fillna('none').value_counts().head(6).to_dict())
print("markets by month:",C.groupby(pd.to_datetime(C.day).dt.to_period('M')).size().to_dict(),flush=True)
D=pd.DataFrame(rows,columns=['state','side','kind','mk','day','ct','sel','p','band','known','x'])
if D.empty: print("ERROR: no trades, so no verdict"); sys.exit(1)
md=sorted(C.day)[len(C)//2]; print(f"trades {len(D)} | markets {D.mk.nunique()} | halves split at {md}",flush=True)
def line(d,**k):
    a=d[d.day<md].x; c=d[d.day>=md].x; e=d[d.p>=1.10].x; kn=d[d.known].x; cl=d.groupby('mk').x.sum()
    r=dict(**k,n=len(d),mkts=d.mk.nunique(),px=d.p.median(),per10=d.x.mean(),t=tstat(d.x),t_c=tstat(cl),n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(c),h2=c.mean() if len(c) else np.nan,known=kn.mean() if len(kn) else np.nan,x110=e.mean() if len(e) else np.nan,max_win=d.x.max())
    r['PASS']=bool(k['state'][0]!='P' and r['n']>=300 and r['n1']>=150 and r['n2']>=150 and r['t']>=3.5 and r['h1']>0 and r['h2']>0 and r['per10']>=0.15 and r['x110']>=0.15)
    return r
out=[]
for (st,sd),b in D.groupby(['state','side']):
    out.append(line(b,state=st,side=sd,cut='all'))
    for bd,x in b.groupby('band'): out.append(line(x,state=st,side=sd,cut=bd))
R=pd.DataFrame(out).sort_values('t',ascending=False); E=R[R.n>=300]
print(f"\n== cells {len(R)}, at n>=300: {len(E)}")
print("\n== HEADLINE, every state and side, all prices\n",R[R.cut=='all'].sort_values(['state','side']).drop(columns=['PASS','cut']).round(3).to_string(index=False))
print("\n== TOP 15 BY t, n>=300, states that can pass\n",E[E.state.str[0]!='P'].head(15).round(3).to_string(index=False))
print("\n== TOP 5 BY t, n>=300, P states (look-ahead, cannot pass)\n",E[E.state.str[0]=='P'].head(5).drop(columns=['PASS']).round(3).to_string(index=False))
W=R[R.PASS]; print(f"\n== SURVIVORS: {len(W)} of {len(R)} cells"); print(W.round(3).to_string(index=False) if len(W) else "none")
PY
