#!/bin/bash
set -o pipefail
# 499_cricket_women (Finder 2026-11-07, queue item 366, Finder's own, source c; engine from jobs/499_cricket_preoff.sh, entries unchanged): women's cricket before the off, by band. Rule pushed in the queue before any price. Read only, no tables written. Item 268's games, so a re-slice and not unseen.
# RESULT inferred as item 268. Each line printed three ways: resolved only, unresolved at last-print odds with the overround removed, unresolved as a loss. A pass needs all three, then official results.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,re,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line
from lib_official import bk,ly,fill,last_in,secs,checks
import lib_cand; lib_cand._checks(); checks()
def infer(last):
    lo=[k for k,v in last.items() if v<=1.10]
    if len(lo)!=1 or len(last)<2: return None
    return lo[0] if all(v>=5.0 for k,v in last.items() if k!=lo[0]) else None
def women(ev): return bool(re.search(r'(^|\s)(W|Women)(\s|$)',ev))
def odds_prob(last,s):
    """Win chance of runner s from last prints, overround removed. By hand: 2.0 v 2.0 gives 0.5; 1.25 v 5 gives 0.8."""
    t=sum(1/v for v in last.values()); return (1/last[s])/t
BANDS=[('<1.5',1.01,1.5),('1.5-2',1.5,2.0),('2-3',2.0,3.0),('3-6',3.0,6.0),('6-20',6.0,20.0)]
def band(p): return next((n for n,lo,hi in BANDS if lo<=p<hi),None)
assert infer({'a':1.05,'b':20})=='a' and infer({'a':1.2,'b':20}) is None and infer({'a':1.05,'b':3}) is None and infer({'a':1.05}) is None
assert women('Delhi Capitals W v Mumbai Indians W') and women('ACT Meteors v Victoria Women') and not women('Canada v USA') and not women('Western Storm v West Indies')
assert abs(odds_prob({'a':2.0,'b':2.0},'a')-.5)<1e-9 and abs(odds_prob({'a':1.25,'b':5.0},'a')-.8)<1e-9
assert band(1.5)=='1.5-2' and band(20) is None and band(5.99)=='3-6'
print("checks: OK",flush=True); T0=time.time()
pd.set_option('display.width',220); pd.set_option('display.max_rows',200); pd.set_option('display.max_columns',30)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
Q0="sport='Cricket' AND market_type='MATCH_ODDS' AND ltp>=1.01 AND ltp<1000 AND market_time>='2024-09-01'"
A=pd.read_sql("SELECT market_id,event_name ev,market_time mt,sel,ts,ltp::float8 ltp,inplay FROM bf_hist_other WHERE "+Q0+" AND NOT inplay AND ts>=market_time-interval '60 minutes'",con)
B=pd.read_sql("SELECT DISTINCT ON (market_id,sel) market_id,event_name ev,market_time mt,sel,ts,ltp::float8 ltp,inplay FROM bf_hist_other WHERE "+Q0+" AND inplay AND ts<=market_time+interval '12 hours' ORDER BY market_id,sel,ts DESC",con); con.close()
P=pd.concat([A,B],ignore_index=True); del A,B
P['tt']=secs(P.ts); P['off']=secs(P.mt); P=P.sort_values('tt',kind='stable').drop_duplicates(['market_id','sel','tt','inplay']); print(f"prints {len(P):,}, markets {P.market_id.nunique():,}, {time.time()-T0:.0f}s",flush=True)
C=Counter(); rows=[]; seen=set()
for m,g in P.groupby('market_id',sort=True):
    ev=g.ev.iloc[0]; o=float(g.off.iloc[0])
    if (ev,o) in seen: C['second id for the game, dropped']+=1; continue
    seen.add((ev,o)); pre=g[~g.inplay]; ip=g[g.inplay]; runners=g.sel.unique()
    if len(runners)!=2: C['not two runners']+=1; continue
    last=ip.groupby('sel').ltp.last().to_dict(); w=infer(last) if len(last)==2 else None; wm=women(ev)
    C['games '+('W' if wm else 'M')+(' resolved' if w is not None else ' unresolved')]+=1
    for s,y in pre.groupby('sel',sort=False):
        ts,px=y.tt.values,y.ltp.values; i=last_in(ts,o-3600,o-120)
        if i is None: C['no print in window']+=1; continue
        for side in 'BL':
            p=fill(ts,px,i,side); b=band(p)
            if p>50 or b is None: C['outside the bands']+=1; continue
            f=(lambda won:bk(p,won)) if side=='B' else (lambda won:ly(p,won))
            vw,vl=f(True),f(False)
            if vw is None or vl is None: C['bottom of ladder']+=1; continue
            if w is not None: v=vw if s==w else vl; lp=v; rs=True; won=(s==w)
            elif len(last)==2: q=odds_prob(last,s); lp=q*vw+(1-q)*vl; v=np.nan; rs=False; won=np.nan
            else: lp=np.nan; v=np.nan; rs=False; won=np.nan
            rows.append((m,ev,o,wm,b,side,p,rs,won,v,lp))
print("counted:",dict(sorted(C.items())),flush=True)
R=pd.DataFrame(rows,columns='m ev off wm b side p rs won v lp'.split()); R['g']=R.ev+R.off.astype(str); md=np.median(R[R.wm].off.values); print("halves split at",pd.Timestamp(md,unit='s',tz='UTC'),flush=True)
def row(nm,x):
    r=x[x.rs]
    if len(r)<2: return None
    l=line(r.v.values,np.where(r.off<md,1,2)); y=x[x.lp.notna()]; o=line(y.lp.values,np.where(y.off<md,1,2)); lw=line(x.v.fillna(-10.0).values,np.where(x.off<md,1,2))
    return dict(line=nm,n=l['n'],games=r.g.nunique(),unres=int((~x.rs).sum()),per10=l['per10'],t=l['t'],h1=l['h1'],h2=l['h2'],maxwin=l['maxwin'],won=r.won.astype(float).mean(),imp=(1/r.p).mean(),lp_n=o['n'],lp_per10=o['per10'],lp_t=o['t'],lp_h1=o['h1'],lp_h2=o['h2'],worst_per10=lw['per10'],worst_t=lw['t'],PASS=bool(l['PASS'] and o['PASS'] and lw['PASS']))
out=[]
for (wm,b,s),x in R.groupby(['wm','b','side']): out.append(dict(row(f"{'W' if wm else 'M'} {b} {'back' if s=='B' else 'lay'}",x),w=wm))
for wm,x in R[(R.side=='L')&(R.p>=3)&(R.p<20)].groupby('wm'): out.append(dict(row(f"{'W' if wm else 'M'} outsider 3-20 lay, item 271's cut, for reference",x),w=wm,ref=True))
O=pd.DataFrame(out); O['ref']=O.get('ref',False)
print(f"\n== item 366, women, by t\n",O[O.w].drop(columns=['w','ref']).sort_values('t',ascending=False).round(3).to_string(index=False))
print(f"\n-- control, men, by t\n",O[~O.w].drop(columns=['w','ref','PASS']).sort_values('t',ascending=False).round(3).to_string(index=False))
S=O[O.w&(O.PASS==True)&(O.ref!=True)]; print(f"\n== SURVIVORS: {len(S)}\n",S.round(3).to_string(index=False) if len(S) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
