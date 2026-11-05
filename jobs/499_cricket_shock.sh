#!/bin/bash
set -o pipefail
# 499_cricket_shock (Finder 2026-11-05, queue item 174; from jobs/493_cricket_mo_basic.sh): fade or follow a wicket-sized in-play shock, closed at a real print. Rule pushed before prices were read (commit 8773b44).
# TAPE: bf_hist_other Cricket MATCH_ODDS, Sep 2024 on, in-play last-traded prints, so a pass is an upper bound; no book. Only markets with exactly two runners with in-play prints.
# SHOCK: first per market per threshold: a runner's print >= (1+X) x its own print at most 180 s earlier, that earlier print <= 5; X 10, 20, 30%. Band on the earlier print.
# ENTRY: that runner's next print strictly after the shock, at most 120 s later, else no trade, counted. One tick adverse. Never the shock's own print, never forward-filled. FADE backs, FOLLOW lays. Lays filling under 1.10 excluded, counted.
# EXIT: first print at or after +10 or +30 min, one tick adverse, or SETTLE. No such print: settled at the result, never dropped.
# RESULT: NO results table covers cricket. Inferred as job 493: one runner's final print <= 1.05 won; two = conflict; else a runner >= 100 lost, the rest unknown. Unknown = -£10 on both sides, shown. Item 67 found final-print inference biased, so a SETTLE line cannot pass, and it is marked no-verdict.
# CONTROL: first runner by name, first print at or after 60 min from the market's first in-play print, within 120 s. Not scored. 2% on profit, £10 risk. Halves by median date. One entry per market per line. One market per event_id, lowest id.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(3_500_000_000,3_500_000_000))  # this job only
import sys,time,warnings,psycopg2,pandas as pd,numpy as np
from collections import Counter
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,line,back_settle,lay_settle,back_hedge,lay_hedge
pd.set_option('display.width',230); pd.set_option('display.max_rows',120); pd.set_option('display.max_columns',30)
T0=time.time(); BUDGET=2400
def result_of(fin):
    """fin: runner -> final in-play print. (runner -> True/False/None, conflict)."""
    w=[s for s,p in fin.items() if p<=1.05]
    if len(w)==1: return {s:s==w[0] for s in fin},False
    if len(w)>1: return {s:None for s in fin},True
    return {s:(False if p>=100 else None) for s,p in fin.items()},False
def first_shock(ts,p,X,win=180.0,cap=5.0):
    """First (i, j): p[i] >= (1+X) p[j], 0 < ts[i]-ts[j] <= win, p[j] <= cap, j scanned from nearest back. None if no shock."""
    for i in range(1,len(p)):
        j=i-1
        while j>=0 and ts[i]-ts[j]<=win:
            if p[j]<=cap and p[i]>=(1+X)*p[j]-1e-9: return i,j
            j-=1
    return None
def next_within(ts,i,lim=120.0):
    return i+1 if i+1<len(ts) and ts[i+1]-ts[i]<=lim else None
def exit_idx(ts,k,hor):
    i=int(np.searchsorted(ts,ts[k]+hor,side='left'))
    return i if i<len(ts) else None
def bandof(p): return '<1.5' if p<1.5 else '1.5-2.5' if p<2.5 else '2.5-5'
def trade(side,x,q,won):
    """Entry print x one tick adverse; q exit print or None=settle; won True/False/None. None=no bet. Unknown result=-10 on both sides."""
    if side=='B':
        a=step(x,-1)
        if a<=1.01: return None
        if q is not None: return back_hedge(a,q)
        return -10.0 if won is None else back_settle(a,won)
    a=step(x,1)
    if a<1.10: return None
    if q is not None: return lay_hedge(a,q)
    return -10.0 if won is None else lay_settle(a,won)
# known answers, worked by hand
assert result_of({'a':1.02,'b':40.})==({'a':True,'b':False},False) and result_of({'a':1.02,'b':1.03})[1] and result_of({'a':3.,'b':120.})==({'a':None,'b':False},False)
_t=np.array([0.,60.,120.,300.,360.])
assert first_shock(_t,[2.0,2.1,2.3,2.3,2.3],0.10)==(2,0)                 # 2.3 < 1.1x2.1=2.31, so nearest j=1 fails; 2.3 >= 1.1x2.0, j=0 at 120 s qualifies
assert first_shock(_t,[2.0,2.0,2.0,2.3,2.3],0.10)==(3,2)                 # j=2 is 180 s back, inside the limit
assert first_shock(np.array([0.,200.]),[2.0,3.0],0.10) is None           # 200 s gap: no shock, no forward fill
assert first_shock(_t,[6.0,9.0,12.,12.,12.],0.10) is None                # earlier print above 5
assert next_within(np.array([0.,100.,300.]),0)==1 and next_within(np.array([0.,100.,300.]),1) is None and next_within(np.array([0.,100.]),1) is None
assert exit_idx(np.array([0.,300.,600.,900.]),0,600.)==2 and exit_idx(np.array([0.,300.]),0,600.) is None
assert bandof(1.49)=='<1.5' and bandof(1.5)=='1.5-2.5' and bandof(2.5)=='2.5-5'
# back 3.0 fills 2.98, out at 2.5 laying 2.52: 10x(2.98/2.52-1)x0.98=1.78889. lay 3.0 fills 3.05, stake 10/2.05; out at 3.5 backing 3.45: stake x (1-3.05/3.45)x0.98.
assert abs(trade('B',3.0,2.5,None)-10*(2.98/2.52-1)*.98)<1e-9 and abs(trade('L',3.0,3.5,None)-10/2.05*(1-3.05/3.45)*.98)<1e-9
assert abs(trade('B',3.0,None,True)-19.404)<1e-9 and trade('B',3.0,None,None)==-10.0 and trade('L',3.0,None,None)==-10.0 and trade('L',3.0,None,True)==-10.0
assert trade('B',1.02,None,True) is None and trade('L',1.05,None,False) is None and abs(trade('L',1.09,None,False)-98.0)<1e-6   # 1.09 fills 1.10: stake 100, wins 98 after 2%
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
cur.execute("SELECT market_id,min(event_id),min(market_time)::date FROM bf_hist_other WHERE sport='Cricket' AND market_type='MATCH_ODDS' AND market_time>='2024-09-01' GROUP BY 1")
M=pd.DataFrame(cur.fetchall(),columns='mid ev day'.split()); dup=len(M)-M.ev.nunique(); M=M.sort_values('mid').drop_duplicates('ev'); MID=M.mid.tolist(); DAY=dict(zip(M.mid,M.day))
print(f"markets {len(MID)}, second markets on one event dropped {dup} | {time.time()-T0:.0f}s",flush=True)
SK=Counter(); rows=[]; XS=(0.10,0.20,0.30); HS=((600.0,'X10'),(1800.0,'X30'),(None,'SETTLE'))
for c_ in range(0,len(MID),500):
    if time.time()-T0>BUDGET: SK['chunks not pulled, budget']+=1; continue
    cur.execute("""SELECT market_id,sel,extract(epoch from ts)::float8,ltp::float8 FROM bf_hist_other WHERE sport='Cricket' AND market_id=ANY(%s) AND market_type='MATCH_ODDS' AND inplay AND ltp>=1.01 AND ltp<=1000""",(MID[c_:c_+500],))
    d=pd.DataFrame(cur.fetchall(),columns='mid sel ts ltp'.split())
    if d.empty: continue
    d=d.drop_duplicates(['mid','sel','ts']).sort_values(['mid','ts'],kind='stable')
    for mk,g in d.groupby('mid',sort=False):
        SK['market with in-play prints']+=1; run={s:(x.ts.values,x.ltp.values.astype(float)) for s,x in g.groupby('sel',sort=False)}
        if len(run)!=2: SK['not two runners']+=1; continue
        SK['two runners']+=1; res,conf=result_of({s:float(v[1][-1]) for s,v in run.items()}); SK['result conflict']+=conf; day=DAY[mk]
        SK['some result unknown']+=any(v is None for v in res.values())
        for X in XS:
            best=None
            for s in sorted(run):
                ts,p=run[s]; h=first_shock(ts,p,X)
                if h is not None and (best is None or ts[h[0]]<best[0]): best=(ts[h[0]],s,h)
            if best is None: continue
            s=best[1]; ts,p=run[s]; i,j=best[2]; SK[f'shock {int(X*100)}']+=1
            k=next_within(ts,i)
            if k is None: SK[f'shock {int(X*100)} no next print in 120 s, no trade']+=1; continue
            for hor,lab in HS:
                e=None if hor is None else exit_idx(ts,k,hor); q=None if e is None else float(p[e])
                for side,rule in (('B','FADE'),('L','FOLLOW')):
                    v=trade(side,float(p[k]),q,res[s])
                    if v is None: SK['no bet, ladder bottom or lay under 1.10']+=1; continue
                    rows.append((f'X{int(X*100)}',bandof(float(p[j])),rule,lab,day,mk,v,e is None,res[s] is None,float(p[k])))
        names=sorted(run); s=names[0]; ts,p=run[s]; t0=min(float(v[0][0]) for v in run.values())
        i=int(np.searchsorted(ts,t0+3600.0,side='left'))
        if i<len(ts) and ts[i]-(t0+3600.0)<=120.0:
            for hor,lab in HS[:2]:
                e=exit_idx(ts,i,hor); q=None if e is None else float(p[e])
                for side,rule in (('B','BACK'),('L','LAY')):
                    v=trade(side,float(p[i]),q,res[s])
                    if v is not None: rows.append(('CONTROL','T60',rule,lab,day,mk,v,e is None,res[s] is None,float(p[i])))
    print(f"  {min(c_+500,len(MID))}/{len(MID)}, rows {len(rows)} | {time.time()-T0:.0f}s",flush=True)
con.close(); print("counts:",dict(sorted(SK.items())),flush=True)
R=pd.DataFrame(rows,columns='x bd rule ex day m v settled unk px'.split())
if R.empty: print("ERROR: no entries, no verdict"); sys.exit(1)
R['when']=pd.to_datetime(R.day).astype('int64'); print(f"dates {R.day.min()}..{R.day.max()}; markets {R.m.nunique()}",flush=True)
out=[]
def add(x,xlab,bd,rule,ex):
    if not len(x): return
    md=np.median(x.when.values); l=line(x.v.values,np.where(x.when.values<md,1,2))
    out.append(dict(x=xlab,band=bd,rule=rule,exit=ex,n=l['n'],per10=l['per10'],t=l['t'],h1=l['h1'],h2=l['h2'],n1=l['n1'],n2=l['n2'],settled=x.settled.mean(),unk=x.unk.mean(),maxwin=l['maxwin'],PASS=bool(l['PASS'] and ex!='SETTLE' and xlab!='CONTROL')))
S0=R[R.x!='CONTROL']
for xl,rule,ex in sorted(set(zip(S0.x,S0.rule,S0.ex))):
    A=S0[(S0.x==xl)&(S0.rule==rule)&(S0.ex==ex)]
    add(A,xl,'ALL',rule,ex)
    for bd in ('<1.5','1.5-2.5','2.5-5'): add(A[A.bd==bd],xl,bd,rule,ex)
for rule,ex in sorted(set(zip(R[R.x=='CONTROL'].rule,R[R.x=='CONTROL'].ex))): add(R[(R.x=='CONTROL')&(R.rule==rule)&(R.ex==ex)],'CONTROL','T60',rule,ex)
S=pd.DataFrame(out).sort_values('t',ascending=False); print(f"\n== ALL {len(S)} LINES (incl. controls), per £10, by t\n",S.round(3).to_string(index=False))
W=S[S.PASS]; print(f"\n== SURVIVORS: {len(W)} of {len(S)}\n",W.round(3).to_string(index=False) if len(W) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
