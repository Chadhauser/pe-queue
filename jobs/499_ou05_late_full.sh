#!/bin/bash
set -o pipefail
# 499_ou05_late_full (Finder 2026-11-08, queue item 454, Finder's own, source b/d, from item 106 which read Sep 2026 only; built from jobs/499_four_goal_under.sh; rule pushed in e4177a7 before any OU0.5 price was read).
# Back or lay Under 0.5 at 0-0. State 0-0: no Over 0.5 print at 1.05 or under before entry.
# Entry: the first Under 0.5 print from E to E+3 min after the first in-play OU print, E = 20, 35, 65, 80, 95 wall-clock minutes, one entry per game per window, each window scored apart.
# Worse of the print and the next within 120 s, one tick adverse, GBP 10 stake or liability, 2%, prices over 50 not traded; official bf_hist_result winner, never dropped for an early settle.
# Read only, no tables written. Prints only, so a pass is an upper bound and earns a real-touch read on liq_sample, not a stake.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line
from lib_official import bk,ly,fill,first_in,secs,checks,group
import lib_cand; lib_cand._checks(); checks()
pd.set_option('display.width',230); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',300)
OU=('OVER_UNDER_05','OVER_UNDER_15','OVER_UNDER_25')
ES=(20,35,65,80,95)
SEL='Under 0.5 Goals'
def state_ok(entry,seen):
    """0-0: Over 0.5 never at 1.05 or under before the entry print (seen = first such print, None if never)."""
    return seen is None or seen>=entry
def window(ip0,E): return (ip0+E*60,ip0+E*60+180)
def band(p):
    if p is None or p!=p: return None
    return 'HIGH' if p<1.7 else ('MID' if p<=2.2 else 'LOW')
# known answers, worked by hand
assert state_ok(1000,None) and state_ok(1000,1000) and state_ok(1000,1500) and not state_ok(1000,999)
assert window(0,20)==(1200,1380) and window(100,95)==(5800,5980)
assert band(1.6)=='HIGH' and band(1.7)=='MID' and band(2.2)=='MID' and band(2.21)=='LOW' and band(None) is None
# Under 0.5 back 1.30 -> 1.29: wins 2.9*0.98=2.842; lay 1.30 -> 1.31: stake 10/0.31, Under loses -> 32.258*0.98=31.613
assert abs(bk(1.30,True)-2.842)<1e-9 and bk(1.30,False)==-10.0 and ly(1.30,True)==-10.0 and abs(ly(1.30,False)-10/0.31*0.98)<1e-9
print("checks: OK",flush=True); T0=time.time()
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
R=pd.read_sql("SELECT market_id,sel,status FROM bf_hist_result WHERE sport='Soccer' AND market_type='OVER_UNDER_05'",con)
w=R[R.status=='WINNER'].groupby('market_id').size(); ok=set(w[w==1].index)
RES={m:dict(zip(g.sel,g.status=='WINNER')) for m,g in R[R.market_id.isin(ok)].groupby('market_id')}
print("official OU0.5 markets",len(RES),"dropped (not one winner)",int(R.market_id.nunique()-len(RES)),f"{time.time()-T0:.0f}s",flush=True); del R
C=Counter(); rows=[]
def months():
    for y,ms in ((2023,range(1,13)),(2024,range(1,11)),(2026,range(4,11))):
        for m in ms:
            a=pd.Timestamp(y,m,1); b=a+pd.offsets.MonthBegin(1)
            for s,e in ((a,a+pd.Timedelta(days=10)),(a+pd.Timedelta(days=10),a+pd.Timedelta(days=20)),(a+pd.Timedelta(days=20),b)): yield str(s.date()),str(e.date())
for lo,hi in months():
    A=pd.read_sql("""SELECT event_id,max(event_name) ev,min(ts) FILTER (WHERE inplay) ip0
                     FROM bf_hist_other WHERE sport='Soccer' AND market_type=ANY(%s) AND market_time>=%s AND market_time<%s
                     AND ts>=market_time-interval '30 minutes' AND ts<=market_time+interval '3 hours' GROUP BY 1""",con,params=(list(OU),lo,hi))
    if A.empty: print(lo,"no rows",flush=True); continue
    U=pd.read_sql("""SELECT market_id,event_id,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type='OVER_UNDER_05'
                     AND sel LIKE 'Under%%' AND inplay AND ltp>=1.01 AND ltp<1000 AND market_time>=%s AND market_time<%s
                     AND ts>=market_time+interval '10 minutes' AND ts<=market_time+interval '150 minutes'""",con,params=(lo,hi))
    S=pd.read_sql("""SELECT event_id,min(ts) t1 FROM bf_hist_other WHERE sport='Soccer' AND market_type='OVER_UNDER_05'
                     AND sel LIKE 'Over%%' AND inplay AND ltp<=1.05 AND market_time>=%s AND market_time<%s
                     AND ts>=market_time-interval '30 minutes' AND ts<=market_time+interval '150 minutes' GROUP BY 1""",con,params=(lo,hi))
    P=pd.read_sql("""SELECT DISTINCT ON (event_id) event_id,ltp::float8 pre FROM bf_hist_other WHERE sport='Soccer' AND market_type='OVER_UNDER_25'
                     AND sel LIKE 'Over%%' AND NOT inplay AND market_time>=%s AND market_time<%s
                     AND ts>=market_time-interval '60 minutes' AND ts<=market_time+interval '10 minutes' ORDER BY event_id,ts DESC""",con,params=(lo,hi))
    U['tt']=secs(U.ts); U=U.sort_values('tt',kind='stable').drop_duplicates(['market_id','tt'])
    S['t1']=secs(S.t1); SEEN=dict(zip(S.event_id,S.t1)); PRE=dict(zip(P.event_id,P.pre))
    UG={k:g for k,g in U.groupby('event_id',sort=False)}
    for e,ev,ip0 in zip(A.event_id,A.ev,A.ip0):
        C['games']+=1
        if not isinstance(ev,str) or ' v ' not in ev: C['no H v A']+=1; continue
        if group(ev): C['women or youth']+=1; continue
        if ip0 is None or ip0!=ip0: C['no in-play prints']+=1; continue
        if e not in UG: C['no OU0.5 under prints']+=1; continue
        ip0s=float(secs(pd.Series([ip0])).iloc[0])
        x=UG[e]; mk=sorted(x.market_id.unique())[0]; x=x[x.market_id==mk]
        if mk not in RES: C['no official']+=1; continue
        if SEL not in RES[mk]: C['sel not in result']+=1; continue
        C['games scored']+=1
        tt=x.tt.values; px=x.ltp.values; seen=SEEN.get(e)
        for E in ES:
            wl,wh=window(ip0s,E); i=first_in(tt,wl,wh)
            if i is None: C[f'E{E} no print in window']+=1; continue
            ent=float(tt[i])
            if not state_ok(ent,seen): continue
            pb=fill(tt,px,i,'B'); pl=fill(tt,px,i,'L')
            if pl>50: C['price over 50']+=1; continue
            won=RES[mk][SEL]
            soon=(seen is not None and seen-ent<=60)
            rows.append(dict(e=e,ev=ev,ip0=ip0s,E=E,band=band(PRE.get(e)),px=float(px[i]),vb=bk(pb,won),vl=ly(pl,won),won=won,soon=soon))
    print(lo,"games",len(A),"under prints",len(U),"trades",len(rows),f"{time.time()-T0:.0f}s",flush=True); del A,U,S,P,UG
con.close(); print("counts",dict(sorted(C.items())),flush=True)
T=pd.DataFrame(rows)
if T.empty: print("\n== SURVIVORS\nnone (no trades)"); sys.exit(0)
med=T.ip0.median(); T['h']=np.where(T.ip0<=med,1,2)
print(f"\nhalves split at {pd.to_datetime(med,unit='s')}; trades {len(T)}, games {T.e.nunique()}")
print("by E: n, median price, Under won, implied\n",T.groupby('E').agg(n=('px','size'),px=('px','median'),won=('won','mean'),imp=('px',lambda s:(1/s).mean())).round(3).to_string())
def row(nm,x,col):
    x=x.dropna(subset=[col]); v=x[col].astype(float).values
    if len(v)<2: return dict(line=nm,n=len(v))
    d=line(v,x.h.values)
    return dict(line=nm,n=d['n'],games=x.e.nunique(),per10=round(d['per10'],3),t=round(d['t'],2),h1=round(d['h1'],3),h2=round(d['h2'],3),n1=d['n1'],n2=d['n2'],
                no_top=round(np.delete(v,v.argmax()).mean(),3),won=round(x.won.astype(float).mean(),3),imp=round((1/x.px).mean(),3),PASS=d['PASS'])
o=[]
for E in ES:
    x=T[T.E==E]
    for col,sd in (('vb','back U0.5'),('vl','lay U0.5')): o.append(row(f'E{E} {sd} *',x,col))
O=pd.DataFrame(o)
print("\n== ITEM 454, ten scored lines\n",O.to_string(index=False))
r=[]
for E in ES:
    for b_ in ('LOW','MID','HIGH'):
        x=T[(T.E==E)&(T.band==b_)]
        for col,sd in (('vb','back U0.5'),('vl','lay U0.5')): r.append(row(f'E{E} {sd} {b_}',x,col))
    x=T[(T.E==E)&(~T.soon)]
    for col,sd in (('vb','back U0.5'),('vl','lay U0.5')): r.append(row(f'E{E} {sd} no goal within 60 s of entry',x,col))
for col,sd in (('vb','back U0.5'),('vl','lay U0.5')): r.append(row(f'all E {sd} (correlated, up to 5 a game)',T,col))
for y in (2023,2024,2026):
    x=T[pd.to_datetime(T.ip0,unit='s').dt.year==y]
    for col,sd in (('vb','back'),('vl','lay')): r.append(row(f'all E {sd} year {y}',x,col))
R_=pd.DataFrame(r); R_=R_[R_.n>=2]
print("\n-- for reading, not scored\n",R_.to_string(index=False))
print("entries with the first Over 1.05 print within 60 s after entry:",int(T.soon.sum()),"of",len(T))
P_=O[O.PASS==True]
print("\n== SURVIVORS"); print(P_.to_string(index=False) if len(P_) else "none",flush=True); print(f"total {time.time()-T0:.0f}s")
PY
