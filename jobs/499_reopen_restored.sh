#!/bin/bash
set -o pipefail
# STRUCK 2026-11-07: total_matched falls at 59 of 59 rows, and returns to the same figure. The book shown is an old snapshot, not one you can trade. See reports/finder_2026-11-07_items265-402.md.
# 499_reopen_restored (Finder 2026-11-07, queue item 399, Finder's own, source a; from jobs/499_reopen_racing.sh): racing, a book restored after the race is decided. Rule pushed in the queue before this split was read. These races suggested it, so nothing can pass here; item 400 is the unseen read. Read only, no tables written. All live tape on Railway. An argument YYYY-MM-DD starts the read at that date, for item 400.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(1_500_000_000,1_500_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
import lib_cand
from lib_cand import line,step
from lib_official import bk,ly,secs,checks
lib_cand._checks(); checks()
START=sys.argv[1] if len(sys.argv)>1 else '2026-10-01'
def group(pre,mid):
    """Which line a row belongs to, or None. Controls sit between 1.20 and 20."""
    if pre<=1.20: return 'WINNER' if mid>=pre*1.15 else None
    if pre>=20: return 'LOSER' if mid<=pre*0.85 else None
    return 'CTRL UP' if mid>=pre*1.15 else 'CTRL DOWN' if mid<=pre*0.85 else None
def real(b,l): return b==b and l==l and b>1.0 and l<=b*1.05
# known answers, worked by hand
assert group(1.01,1.5)=='WINNER' and group(1.20,1.38)=='WINNER' and group(1.20,1.37) is None and group(30,20)=='LOSER' and group(20,17.1) is None and group(20,17)=='LOSER'
assert group(3,4)=='CTRL UP' and group(3,2.5)=='CTRL DOWN' and group(3,3.2) is None and group(1.21,2) =='CTRL UP'
assert real(1.5,1.51) and not real(1.5,1.6) and not real(float('nan'),2)
assert abs(bk(1.5,True)-(1.49-1)*10*.98)<1e-9 and bk(1.5,False)==-10.0 and abs(ly(10,False)-10/9.5*.98)<1e-9 and ly(10,True)==-10.0
print("checks: OK",flush=True); T0=time.time()
pd.set_option('display.width',220); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',60)
rc=psycopg2.connect(creds.pg_railway(),sslmode='require'); rc.autocommit=True; rc.cursor().execute("SET statement_timeout='300s'")
A=pd.read_sql("SELECT ts,market_id,event_name ev,sel_id,sel_name,secs_since_start ss,pre_ltp::float8 pre,post_back_px::float8 b,post_lay_px::float8 l FROM ip_reopen WHERE sport IN ('horse_racing','racing') AND market_type='WIN' AND ts>=%s ORDER BY ts",rc,params=(START,))
W=pd.read_sql("SELECT market_id,selection_id sel_id,won,bsp::float8 bsp FROM racing_results WHERE market_id=ANY(%s)",rc,params=(list(A.market_id.unique()),))
wc=W.assign(w=W.won.eq(True)).groupby('market_id').w.sum(); ok=set(wc[wc==1].index)
print(f"reopen rows {len(A):,}, markets {A.market_id.nunique():,}, with one winner {len(ok)}; {time.time()-T0:.0f}s",flush=True)
A['tt']=secs(A.ts); F0=A.groupby('market_id').tt.min(); A=A[A.market_id.isin(ok)].merge(W,on=['market_id','sel_id'],how='left')
C=Counter(); rows=[]; seen=set()
for r in A.itertuples():
    if r.pre!=r.pre or r.pre<=1: C['no pre_ltp']+=1; continue
    if not real(r.b,r.l): C['no real book']+=1; continue
    if r.won is None or r.won!=r.won: C['no result for the runner']+=1; continue
    mid=0.5*(r.b+r.l); g=group(r.pre,mid)
    if g is None: C['no group']+=1; continue
    if (g,r.market_id,r.sel_id) in seen: C['later row, same runner and group']+=1; continue
    seen.add((g,r.market_id,r.sel_id)); won=bool(r.won)
    rows.append(dict(g=g,m=r.market_id,sel=r.sel_id,off=r.tt,ev=r.ev,name=r.sel_name,pre=r.pre,b=r.b,l=r.l,mid=mid,bsp=r.bsp,won=won,vb=bk(r.b,won),vl=ly(r.l,won),vb3=bk(step(r.b,-2),won),vl3=ly(step(r.l,2),won),gap=r.tt-F0[r.market_id],ss=r.ss,ts=r.ts))
print("counted:",dict(sorted(C.items())),flush=True)
T=pd.DataFrame(rows); assert not T.duplicated(['g','m','sel']).any(); md=float(np.median(T.drop_duplicates('m').off)); print("races",T.m.nunique(),"split at",pd.Timestamp(md,unit='s',tz='UTC'),flush=True)
out=[]
def rd(nm,x,c,imp,scored):
    z=x[x[c].notna()]
    if len(z)<2: return
    # t by race: mean per race first, as one race can hold two runners
    h=np.where(z.off<md,1,2); l=line(z[c].astype(float).values,h); g_=z.groupby('m')[c].sum().astype(float); tr=float(g_.mean()/(g_.std(ddof=1)/np.sqrt(len(g_)))) if len(g_)>2 and g_.std(ddof=1)>0 else float('nan')
    out.append(dict(line=nm,n=l['n'],races=z.m.nunique(),per10=l['per10'],t=l['t'],t_race=tr,n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],maxwin=l['maxwin'],won=z.won.mean(),imp=(1/z[imp]).mean(),PASS=bool(l['PASS'] and scored and tr>=3.5)))
for g,x in T.groupby('g'):
    sc=g in('WINNER','LOSER')
    if g=='WINNER': rd('WINNER back (scored)',x,'vb','b',sc); rd('WINNER back 3 ticks, stress',x,'vb3','b',False)
    elif g=='LOSER': rd('LOSER lay (scored)',x,'vl','l',sc); rd('LOSER lay 3 ticks, stress',x,'vl3','l',False)
    else: rd(g+' back, control',x,'vb','b',False); rd(g+' lay, control',x,'vl','l',False)
O=pd.DataFrame(out); print("\n"+O.sort_values('t',ascending=False).round(3).to_string(index=False))
print("\nwhere the book sits and when:")
print(T.assign(mb=T.mid/T.bsp).groupby('g').agg(n=('mb','size'),mid_v_bsp=('mb','median'),pre=('pre','median'),mid=('mid','median'),secs_since_first_reopen=('gap','median'),secs_since_sched=('ss','median')).round(2).to_string())
W_=T[T.g=='WINNER'].sort_values('off').tail(12)[['ev','name','pre','b','l','bsp','won','gap']]; print("\nlatest WINNER rows\n",W_.round(2).to_string(index=False))
print("\nby price, WINNER back:",T[T.g=='WINNER'].groupby(pd.cut(T[T.g=='WINNER'].b,[1,1.5,2.5,5,1000])).agg(n=('vb','size'),per10=('vb','mean'),won=('won','mean')).round(3).to_dict('index'))
print("by price, LOSER lay:",T[T.g=='LOSER'].groupby(pd.cut(T[T.g=='LOSER'].l,[1,5,10,20,1000])).agg(n=('vl','size'),per10=('vl','mean'),won=('won','mean')).round(3).to_dict('index'))
W2=T[T.g.isin(['WINNER','LOSER'])&(T.off>=time.time()-5.5*86400)]
if len(W2):
    rc=psycopg2.connect(creds.pg_railway(),sslmode='require'); rc.cursor().execute("SET statement_timeout='300s'")
    P=pd.read_sql("SELECT ts,market_id m,sel_id sel,back_px::float8 bp,back_sz::float8 bs,lay_px::float8 lp,lay_sz::float8 ls,status FROM ip_tape WHERE market_id=ANY(%s) AND sel_id=ANY(%s) ORDER BY ts",rc,params=(list(W2.m.unique()),[int(x) for x in W2.sel.unique()])); rc.close(); P['tt']=secs(P.ts); o=[]
    for r in W2.itertuples():
        y=P[(P.m==r.m)&(P.sel==r.sel)]; a=y[(y.tt>=r.off-1)&(y.tt<=r.off+1)]; nx=y[(y.tt>r.off+1)&(y.tt<=r.off+30)]
        o.append(dict(g=r.g,size=float(a.bs.iloc[0]) if r.g=='WINNER' and len(a) else (float(a.ls.iloc[0]) if len(a) else np.nan),on_tape=len(a)>0,next_status=nx.status.iloc[-1] if len(nx) else None,still=(nx.bp.max()>=r.b if r.g=='WINNER' else nx.lp.min()<=r.l) if len(nx) else None))
    q=pd.DataFrame(o); print("\nsize on show at the row, ip_tape rolling window:",q.groupby('g').agg(rows=('size','size'),on_tape=('on_tape','sum'),size_median=('size','median'),still_there_30s=('still',lambda s:s.dropna().astype(float).mean())).round(2).to_string())
S=O[O.PASS==True]; print(f"\n== SURVIVORS: {len(S)} of 2\n",S.round(3).to_string(index=False) if len(S) else "none"); print("These races suggested the lines, so a number here is not a pass: item 400."); print(f"total {time.time()-T0:.0f}s")
PY
