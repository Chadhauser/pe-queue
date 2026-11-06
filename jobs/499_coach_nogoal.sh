#!/bin/bash
set -o pipefail
# 499_coach_nogoal (Finder 2026-11-06, queue item 325, Finder's own, source a): MO runner moving in play with the score unchanged, real touch from coach_path. Rule pushed in the queue before any trade. Read only. Eight days of tape: a pass earns a re-read on later dates, not a stake.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(1_500_000_000,1_500_000_000))  # this job only
import sys,re,time,warnings,psycopg2,pandas as pd,numpy as np
from collections import Counter,defaultdict
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,line,back_settle,lay_settle,back_hedge,lay_hedge
pd.set_option('display.width',240); pd.set_option('display.max_columns',30)
T0=time.time()
def mid(b,l): return (b+l)/2
def state(m0,m1):
    r=round(m1/m0-1,9)   # so an exact 5% or 15% is not lost to float error
    return 'SHORT' if r<=-0.15 else 'LONG' if r>=0.25 else 'FLAT' if abs(r)<=0.05 else None
def result(score):
    a=re.match(r"^(\d+)-(\d+)$",str(score))
    if not a: return None
    h,x=int(a[1]),int(a[2])
    return 'HOME' if h>x else 'AWAY' if x>h else 'DRAW'
def trade(side,b,l,won,bx,lx):
    """Touch at entry b,l. Exit touch bx,lx, or None to settle at the result. Returns P&L per £10 risk."""
    if side=='B':
        a=step(b,-1)
        return None if a<=1.01 else (back_settle(a,won) if lx is None else back_hedge(a,lx))
    a=step(l,1)
    return lay_settle(a,won) if bx is None else lay_hedge(a,bx)
# known answers, worked by hand
assert mid(2.0,2.2)==2.1 and state(2.0,1.7)=='SHORT' and state(2.0,1.71) is None and state(2.0,2.5)=='LONG' and state(2.0,2.49) is None and state(2.0,2.1)=='FLAT' and state(2.0,1.9)=='FLAT' and state(2.0,1.89) is None
assert result('2-1')=='HOME' and result('0-3')=='AWAY' and result('1-1')=='DRAW' and result('x') is None
# Back at touch 3.0: fills 2.98. Out by laying touch 2.0, fills 2.02: back_hedge 4.657426 (lib_cand's worked figure). Result: 2.98 win 19.404, lose -10.
assert abs(trade('B',3.0,3.1,None,None,2.0)-4.657426)<1e-5 and abs(trade('B',3.0,3.1,True,None,None)-19.404)<1e-9 and trade('B',3.0,3.1,False,None,None)==-10.0
# Lay at touch 3.0: fills 3.05. Out by backing touch 5.0, fills 4.9: 1.804878. Result: runner loses +4.780488, wins -10.
assert abs(trade('L',2.9,3.0,None,5.0,None)-1.804878)<1e-5 and abs(trade('L',2.9,3.0,False,None,None)-4.780488)<1e-5 and trade('L',2.9,3.0,True,None,None)==-10.0
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
d=pd.read_sql("SELECT DISTINCT tape_date,match,sel,minute,score,back_px::float8 b,lay_px::float8 l FROM coach_path WHERE mkt='MO'",con); con.close()
n0=len(d); d=d.drop_duplicates(['tape_date','match','sel','minute'],keep=False); print(f"MO rows {n0}; after dropping ambiguous duplicates {len(d)}; games {d.drop_duplicates(['tape_date','match']).shape[0]}; dates {d.tape_date.min()}..{d.tape_date.max()}",flush=True)
SK=Counter(); rows=[]
for (td,ma),g in d.groupby(['tape_date','match'],sort=False):
    last=g[g.minute==90]; res=result(last.score.iloc[0]) if len(last) and last.score.nunique()==1 else None
    if res is None: SK['game, no minute-90 result']+=1
    else: SK['game, result']+=1
    for sel in ('HOME','AWAY'):
        x=g[g.sel==sel].sort_values('minute'); B={r.minute:r for r in x.itertuples()}; done=set()
        for m in (15,30,45,60):
            if m not in B or m-15 not in B: continue
            r0,r1=B[m-15],B[m]
            if r0.score!=r1.score or not(0<r0.b<=r0.l) or not(0<r1.b<=r1.l): continue
            mm=mid(r1.b,r1.l)
            if not(1.5<=mm<=8) or r1.l/r1.b>1.10: continue
            st=state(mid(r0.b,r0.l),mm)
            if st is None or st in done: continue
            done.add(st); SK[f'trigger {st}']+=1
            later=[B[k] for k in sorted(B) if k>m]; nx=later[0] if later else None
            won=None if res is None else res==sel
            for side in 'BL':
                # exit A: next row, else result; exit B: the result
                if nx is not None and nx.b>0 and nx.l>0: va=trade(side,r1.b,r1.l,None,nx.b,nx.l)
                elif won is not None: va=trade(side,r1.b,r1.l,won,None,None)
                else: va=None; SK['exit A, no exit and no result']+=1
                vb=trade(side,r1.b,r1.l,won,None,None) if won is not None else None
                if won is None: SK['exit B, no result, not scored']+=1
                rows.append((st,side,td,ma,sel,m,mm,va,vb))
print("counts:",dict(sorted(SK.items())),flush=True)
R=pd.DataFrame(rows,columns='st side day match sel m px A B'.split())
if R.empty: print("ERROR: no rows, no verdict"); sys.exit(1)
assert not R.duplicated(['st','side','day','match','sel']).any(),"more than one bet per runner per line"
R['when']=pd.to_datetime(R.day).astype('int64'); out=[]
for (st,side),x in R.groupby(['st','side']):
    for ex in 'AB':
        y=x[x[ex].notna()]
        if len(y)<2: continue
        md=np.median(y.when.values); h=np.where(y.when.values<md,1,2); l=line(y[ex].values,h)
        out.append(dict(st=st,side=side,exit=ex,n=l['n'],per10=l['per10'],t=l['t'],h1=l['h1'],h2=l['h2'],n1=l['n1'],n2=l['n2'],games=y.drop_duplicates(['day','match']).shape[0],px=y.px.mean(),PASS=bool(l['PASS'])))
S=pd.DataFrame(out).sort_values('t',ascending=False); A=S[S.st!='FLAT']
print(f"\n== ITEM 325: {len(A)} lines\n",A.round(3).to_string(index=False))
print("\n-- control FLAT, cannot pass\n",S[S.st=='FLAT'].drop(columns='PASS').round(3).to_string(index=False))
W=A[A.PASS]; print(f"\n== SURVIVORS 325: {len(W)} of {len(A)}\n",W.round(3).to_string(index=False) if len(W) else "none",flush=True)
print(f"total {time.time()-T0:.0f}s")
PY
