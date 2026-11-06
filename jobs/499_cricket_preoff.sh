#!/bin/bash
set -o pipefail
# 499_cricket_preoff (Finder 2026-11-06, queue item 268, Finder's own, source d): cricket before the off, held to an INFERRED result, by band. Rule pushed in the queue (ae1146f) before any price. Read only. No tables written.
# ENTRY last non-in-play print T-60 to T-2, worse of it and the next within 120 s, one tick adverse, 2%, GBP 10. Over 50 not traded.
# RESULT no official cricket result on the box: winner = last in-play print <= 1.10 with every other runner's >= 5.0, within 12 h of the off (a Test match runs past this, so Tests mostly land in unresolved). Anything else unresolved, counted by band. Each scored line is shown twice: resolved trades only, and with every unresolved trade as a loss. A pass needs both.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line
from lib_official import bk,ly,fill,last_in,secs,checks
import lib_cand; lib_cand._checks(); checks()
def infer(last):
    """{runner: last in-play print} -> the winner, or None. By hand: 1.05 v 20 is the first; 1.2 v 20 and 1.05 v 3 are unresolved; two low prints are unresolved."""
    lo=[k for k,v in last.items() if v<=1.10]
    if len(lo)!=1 or len(last)<2: return None
    return lo[0] if all(v>=5.0 for k,v in last.items() if k!=lo[0]) else None
assert infer({'a':1.05,'b':20})=='a' and infer({'a':1.2,'b':20}) is None and infer({'a':1.05,'b':3}) is None and infer({'a':1.05,'b':1.08}) is None and infer({'a':1.05}) is None and infer({'a':1.02,'b':30,'c':900})=='a'
def band(p): return next((n for n,lo,hi in BANDS if lo<=p<hi),None)
BANDS=[('<1.5',1.01,1.5),('1.5-2',1.5,2.0),('2-3',2.0,3.0),('3-6',3.0,6.0),('6-20',6.0,20.0)]
assert band(1.5)=='1.5-2' and band(1.49)=='<1.5' and band(20) is None and band(5.99)=='3-6'
print("checks: OK",flush=True); T0=time.time()
pd.set_option('display.width',220); pd.set_option('display.max_rows',200); pd.set_option('display.max_columns',30)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
# FIX 2026-11-06, the brief's one fix: MemoryError reading every in-play print. Only the last in-play print per runner is used, so SQL now returns that alone. No change to the rule.
Q0="sport='Cricket' AND market_type='MATCH_ODDS' AND ltp>=1.01 AND ltp<1000 AND market_time>='2024-09-01'"
A=pd.read_sql("SELECT market_id,event_name ev,market_time mt,sel,ts,ltp::float8 ltp,inplay FROM bf_hist_other WHERE "+Q0+" AND NOT inplay AND ts>=market_time-interval '60 minutes'",con)
B=pd.read_sql("SELECT DISTINCT ON (market_id,sel) market_id,event_name ev,market_time mt,sel,ts,ltp::float8 ltp,inplay FROM bf_hist_other WHERE "+Q0+" AND inplay AND ts<=market_time+interval '12 hours' ORDER BY market_id,sel,ts DESC",con); con.close()
P=pd.concat([A,B],ignore_index=True); del A,B
P['tt']=secs(P.ts); P['off']=secs(P.mt); P=P.sort_values('tt',kind='stable').drop_duplicates(['market_id','sel','tt','inplay']); print(f"prints {len(P):,}, markets {P.market_id.nunique():,}, {time.time()-T0:.0f}s",flush=True)
C=Counter(); rows=[]; seen=set()
for m,g in P.groupby('market_id',sort=True):
    ev=g.ev.iloc[0]; o=float(g.off.iloc[0])
    if (ev,o) in seen: C['second id for the game, dropped']+=1; continue
    seen.add((ev,o)); pre=g[~g.inplay]; ip=g[g.inplay]; home=ev.partition(' v ')[0].strip(); runners=g.sel.unique()
    nr=len(runners); last=ip.groupby('sel').ltp.last().to_dict(); w=infer(last) if nr>=2 and len(last)==nr else None
    if w is None: C['game unresolved']+=1
    else: C['game resolved']+=1
    for s,y in pre.groupby('sel',sort=False):
        ts,px=y.tt.values,y.ltp.values; i=last_in(ts,o-3600,o-120)
        if i is None: C['no print in window']+=1; continue
        for side in 'BL':
            p=fill(ts,px,i,side); b=band(p)
            if p>50: C['over 50']+=1; continue
            if b is None: C['outside the bands']+=1; continue
            won=None if w is None else (s==w); v=None
            if w is not None:
                v=bk(p,won) if side=='B' else ly(p,won)
                if v is None: C['bottom of ladder']+=1; continue
            rows.append((m,o,'3R' if nr>=3 else '2R',b,side,s==home,p,won,v))
print("counted:",dict(sorted(C.items())),flush=True)
R=pd.DataFrame(rows,columns='m off r b side first p won v'.split()); md=np.median(R.off.values); print("halves split at",pd.Timestamp(md,unit='s',tz='UTC'),flush=True)
def row(nm,x):
    u=x.v.isna(); r=x[~u]
    if len(r)<2: return None
    l=line(r.v.values,np.where(r.off<md,1,2)); worst=x.v.fillna(-10.0).values; lw=line(worst,np.where(x.off<md,1,2))
    return dict(line=nm,n=l['n'],unres=int(u.sum()),per10=l['per10'],t=l['t'],h1=l['h1'],h2=l['h2'],maxwin=l['maxwin'],won=r.won.astype(float).mean(),imp=(1/r.p).mean(),worst_per10=lw['per10'],worst_t=lw['t'],PASS=bool(l['PASS'] and lw['PASS']))
out=[]
for (r_,b,s),x in R.groupby(['r','b','side']): out.append(row(f"{r_} {b} {'back' if s=='B' else 'lay'}",x))
for (r_,f,s),x in R[R.r=='2R'].groupby(['r','first','side']): out.append(row(f"2R {'first named' if f else 'second named'} {'back' if s=='B' else 'lay'}",x))
O=pd.DataFrame([z for z in out if z]); print(f"\n== {len(O)} lines by t"); print(O.sort_values('t',ascending=False).round(3).to_string(index=False))
print("\n== share unresolved by band, 2R back rows, a skew here is the bias to watch"); y=R[(R.r=='2R')&(R.side=='B')]; print(y.groupby('b').v.apply(lambda z:round(z.isna().mean(),3)).to_dict())
S=O[O.PASS==True]; print(f"\n== SURVIVORS: {len(S)} of {len(O)}\n",S.round(3).to_string(index=False) if len(S) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
