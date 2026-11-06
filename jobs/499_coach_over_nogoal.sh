#!/bin/bash
set -o pipefail
# 499_coach_over_nogoal (Finder 2026-11-06, queue item 328, Finder's own, source a, from jobs/499_coach_nogoal.sh): Over line shortening with the score unchanged, real touch from coach_path. Rule pushed in the queue before any trade. Read only. Eight days of tape: a pass earns a re-read on later dates, not a stake.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(1_500_000_000,1_500_000_000))  # this job only
import sys,re,time,warnings,psycopg2,pandas as pd,numpy as np
from collections import Counter
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,line,back_settle,lay_settle,back_hedge,lay_hedge
pd.set_option('display.width',240); pd.set_option('display.max_columns',30)
T0=time.time()
LINE={'OU15':1.5,'OU25':2.5,'OU35':3.5}
def mid(b,l): return (b+l)/2
def state(m0,m1):
    r=round(m1/m0-1,9)   # so an exact 5% or 10% is not lost to float error
    return 'SHORT' if r<=-0.10 else 'FLAT' if abs(r)<=0.05 else None
def goals(score):
    a=re.match(r"^(\d+)-(\d+)$",str(score))
    return None if not a else int(a[1])+int(a[2])
def trade(side,b,l,won,bx,lx):
    """Touch at entry b,l. Exit touch bx,lx, or None to settle at the result. Returns P&L per £10 risk."""
    if side=='B':
        a=step(b,-1)
        return None if a<=1.01 else (back_settle(a,won) if lx is None else back_hedge(a,lx))
    a=step(l,1)
    return lay_settle(a,won) if bx is None else lay_hedge(a,bx)
def over_won(maxg,g90,ln):
    """True once any row of the game shows goals over the line; False only with a minute-90 row at or under it; else None."""
    if maxg is not None and maxg==maxg and maxg>ln: return True
    if g90 is not None and g90==g90: return False
    return None
# known answers, worked by hand
assert over_won(3,None,2.5) is True and over_won(2,2,2.5) is False and over_won(2,None,2.5) is None and over_won(None,None,2.5) is None and over_won(float('nan'),None,2.5) is None and over_won(1,1,1.5) is False and over_won(2,1,1.5) is True
assert state(2.0,1.8)=='SHORT' and state(2.0,1.81) is None and state(2.0,2.1)=='FLAT' and state(2.0,1.9)=='FLAT' and state(2.0,1.89) is None and state(2.0,2.2) is None
assert goals('2-1')==3 and goals('0-0')==0 and goals('x') is None
assert goals('2-1')>LINE['OU25'] and not goals('1-1')>LINE['OU25'] and goals('1-1')>LINE['OU15']
assert abs(trade('B',3.0,3.1,None,None,2.0)-4.657426)<1e-5 and abs(trade('B',3.0,3.1,True,None,None)-19.404)<1e-9 and trade('B',3.0,3.1,False,None,None)==-10.0
assert abs(trade('L',2.9,3.0,None,5.0,None)-1.804878)<1e-5 and abs(trade('L',2.9,3.0,False,None,None)-4.780488)<1e-5 and trade('L',2.9,3.0,True,None,None)==-10.0
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
d=pd.read_sql("SELECT DISTINCT tape_date,match,mkt,sel,minute,score,back_px::float8 b,lay_px::float8 l FROM coach_path WHERE mkt IN ('OU15','OU25','OU35')",con); con.close()
print("selections:",d.groupby('mkt').sel.unique().apply(list).to_dict(),flush=True)
# FIX after the first read: an Over line stops printing once a goal settles it, so a result read off that line's own minute-90 row drops the games the Over won. Score now comes from every market of the game.
con=psycopg2.connect(creds.pg_local()); Z=pd.read_sql("SELECT DISTINCT tape_date,match,minute,score FROM coach_path",con); con.close()
Z['g']=Z.score.map(goals); MAXG=Z.groupby(['tape_date','match']).g.max().to_dict()
z9=Z[Z.minute==90].dropna(subset=['g']).groupby(['tape_date','match']).g.max(); G90=z9.to_dict()
print(f"games {len(MAXG)}; with a minute-90 row in any market {len(G90)}",flush=True)
d=d[d.sel.astype(str).str.upper().str.startswith('OVER')]
n0=len(d); d=d.drop_duplicates(['tape_date','match','mkt','minute'],keep=False); print(f"Over rows {n0}; after dropping ambiguous duplicates {len(d)}; games {d.drop_duplicates(['tape_date','match']).shape[0]}; dates {d.tape_date.min()}..{d.tape_date.max()}",flush=True)
SK=Counter(); rows=[]
for (td,ma,mk),x in d.groupby(['tape_date','match','mkt'],sort=False):
    x=x.sort_values('minute'); B={r.minute:r for r in x.itertuples()}; done=set()
    won=over_won(MAXG.get((td,ma)),G90.get((td,ma)),LINE[mk])
    SK['line, result' if won is not None else 'line, no result']+=1
    if won: SK['line, Over won']+=1
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
        for side in 'BL':
            if nx is not None and nx.b>0 and nx.l>0: va=trade(side,r1.b,r1.l,None,nx.b,nx.l)
            elif won is not None: va=trade(side,r1.b,r1.l,won,None,None)
            else: va=None; SK['next-row exit, no row and no result']+=1
            vb=trade(side,r1.b,r1.l,won,None,None) if won is not None else None
            if won is None: SK['result exit, no result, not scored']+=1
            rows.append((mk,st,side,td,ma,m,mm,va,vb))
print("counts:",dict(sorted(SK.items())),flush=True)
R=pd.DataFrame(rows,columns='mkt st side day match m px A B'.split())
if R.empty: print("ERROR: no rows, no verdict"); sys.exit(1)
assert not R.duplicated(['mkt','st','side','day','match']).any(),"more than one bet per game per line"
R['when']=pd.to_datetime(R.day).astype('int64'); out=[]
for (mk,st,side),x in R.groupby(['mkt','st','side']):
    for ex in 'AB':
        y=x[x[ex].notna()]
        if len(y)<2: continue
        md=np.median(y.when.values); h=np.where(y.when.values<md,1,2); l=line(y[ex].values,h)
        out.append(dict(mkt=mk,st=st,side=side,exit='next' if ex=='A' else 'result',n=l['n'],per10=l['per10'],t=l['t'],h1=l['h1'],h2=l['h2'],n1=l['n1'],n2=l['n2'],games=y.drop_duplicates(['day','match']).shape[0],px=y.px.mean(),PASS=bool(l['PASS'] and ex=='A')))
S=pd.DataFrame(out).sort_values('t',ascending=False); A=S[S.st=='SHORT']
print(f"\n== ITEM 328: {len(A)} lines; only a next-row exit can pass, as the rule says\n",A.round(3).to_string(index=False))
print("\n-- control FLAT, cannot pass\n",S[S.st=='FLAT'].drop(columns='PASS').round(3).to_string(index=False))
W=A[A.PASS]; print(f"\n== SURVIVORS 328: {len(W)} of {len(A)}\n",W.round(3).to_string(index=False) if len(W) else "none",flush=True)
print(f"total {time.time()-T0:.0f}s")
PY
