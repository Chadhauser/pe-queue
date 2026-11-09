#!/bin/bash
set -o pipefail
# 499_round_number_preoff (Finder 2026-11-09, 04:50 UTC run, queue item 482, Finder's own, source c structural; rule pushed in the queue before this job read a price).
# Does a runner whose last pre-off print sits exactly on a round price (1.5 2 2.5 3 4 5 6 8 10 15 20) win at a different rate from its implied price?
# Soccer MATCH_ODDS (3 runners) and OVER_UNDER_25 (2 runners). Last pre-off print of each runner within 30 min before market_time, price 1.2-20.5.
# ROUND = print on the set; NEAR = one tick either side of a round (reading control). One bet a market: the qualifying runner with the latest print.
# One tick adverse, £10 stake or liability, 2% on profit, held to the market's own official result (bf_hist_result, one winner), never dropped.
# Women and youth out. Halves by date median. Scored lines (4): MO ROUND back/lay, OU25 ROUND back/lay. Read only, no tables written. Prints only.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,gc,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line,step
from lib_official import ly,bk,secs,checks,group,load_results
import lib_cand; lib_cand._checks(); checks()
pd.set_option('display.width',230); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',200)
MKTS=('MATCH_ODDS','OVER_UNDER_25')
ROUND=(1.5,2.0,2.5,3.0,4.0,5.0,6.0,8.0,10.0,15.0,20.0)
NEAR={}
for r in ROUND:
    NEAR[round(step(r,-1),2)]=r; NEAR[round(step(r,1),2)]=r
def cls(p):
    """-> ('ROUND', r) / ('NEAR', r) / ('OTHER', None) / None outside 1.2-20.5."""
    if p<1.2 or p>20.5: return None
    q=round(float(p),2)
    if any(abs(q-r)<1e-9 for r in ROUND): return 'ROUND',q
    if q in NEAR: return 'NEAR',NEAR[q]
    return 'OTHER',None
# known answers, worked by hand on the Betfair ladder
assert round(step(2.0,-1),2)==1.99 and round(step(2.0,1),2)==2.02 and round(step(3.0,1),2)==3.05 and round(step(10.0,-1),2)==9.8 and round(step(10.0,1),2)==10.5
assert cls(2.0)==('ROUND',2.0) and cls(1.99)==('NEAR',2.0) and cls(2.02)==('NEAR',2.0) and cls(2.04)==('OTHER',None)
assert cls(4.9)==('NEAR',5.0) and cls(5.1)==('NEAR',5.0) and cls(19.5)==('NEAR',20.0) and cls(21.0) is None and cls(1.19) is None
assert cls(1.49)==('NEAR',1.5) and cls(1.51)==('NEAR',1.5) and cls(14.5)==('NEAR',15.0) and cls(7.8)==('NEAR',8.0)
assert len(NEAR)==2*len(ROUND)
# back 3.0 -> 2.98 wins 19.8*0.98=19.404; lay 3.0 -> 3.05: stake 10/2.05, wins 4.7805 after 2%
assert abs(bk(3.0,True)-19.8*0.98)<1e-9 and bk(3.0,False)==-10.0 and abs(ly(3.0,False)-10/2.05*0.98)<1e-9 and ly(3.0,True)==-10.0
print("checks: OK",flush=True); T0=time.time()
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
RS={}
for mt in MKTS:
    r,dr=load_results(con,[mt]); RS.update(r); print("official",mt,len(r),"dropped (no single winner)",dr,flush=True)
C=Counter(); rows=[]
def chunks():
    for y,ms in ((2022,range(8,13)),(2023,range(1,13)),(2024,range(1,11)),(2026,range(5,11))):
        for m in ms:
            a=pd.Timestamp(y,m,1); e=a+pd.offsets.MonthBegin(1)
            while a<e:
                b=min(a+pd.Timedelta(days=5),e); yield str(a.date()),str(b.date()); a=b
for lo,hi in chunks():
    X=pd.read_sql("""SELECT market_id,event_name ev,market_type mkt,market_time mt,sel,ts,ltp::float8 ltp FROM bf_hist_other
                     WHERE sport='Soccer' AND market_type=ANY(%s) AND market_time>=%s AND market_time<%s AND NOT inplay
                       AND ts>=market_time-interval '30 minutes' AND ts<=market_time AND ltp>=1.01 AND ltp<1000""",
                  con,params=(list(MKTS),lo,hi))
    if X.empty: continue
    X['tt']=secs(X.ts); X['off']=secs(X.mt); X=X.sort_values('tt',kind='stable')
    L=X.groupby(['market_id','sel'],sort=False).tail(1)   # last pre-off print of each runner
    # a tie at the last second with two prices is ambiguous: count those runners and skip them
    tie=X.merge(L[['market_id','sel','tt']],on=['market_id','sel','tt']).groupby(['market_id','sel']).ltp.nunique()
    amb=set(tie[tie>1].index); C['runners tied last second']+=len(amb)
    for mid,G in L.groupby('market_id',sort=False):
        C['markets']+=1; ev=G.ev.iloc[0]; mk=G.mkt.iloc[0]
        if not isinstance(ev,str) or ' v ' not in ev: C['no H v A']+=1; continue
        if group(ev): C['women or youth']+=1; continue
        if mid not in RS: C['no official']+=1; continue
        res=RS[mid]
        for kind in ('ROUND','NEAR','ALL'):
            best=None
            for x in G.itertuples(index=False):
                if (mid,x.sel) in amb: continue
                c=cls(x.ltp)
                if c is None: continue
                if kind!='ALL' and c[0]!=kind: continue
                if best is None or x.tt>best.tt: best=x
            if best is None: continue
            if best.sel not in res: C[f'{kind} sel not in result']+=1; continue
            won=bool(res[best.sel]); c=cls(best.ltp)
            rows.append(dict(kind=kind,mkt=mk,ev=ev,mid=mid,off=float(best.off),sel=best.sel,px=float(best.ltp),rnd=c[1],won=won,
                             vb=bk(best.ltp,won),vl=ly(best.ltp,won),mins=(float(best.off)-best.tt)/60))
    del X,L; gc.collect()
    if lo.endswith('-01'): print(lo,"rows",len(rows),f"{time.time()-T0:.0f}s",flush=True)
con.close(); print("counts",dict(sorted(C.items())),flush=True)
T=pd.DataFrame(rows); T['yr']=pd.to_datetime(T.off,unit='s').dt.year
print("bets by kind and market\n",T.groupby(['kind','mkt']).size().to_string())
def row(nm,x,side):
    x=x.dropna(subset=[side]); v=x[side].astype(float).values
    if len(v)<2: return dict(line=nm,n=len(v))
    med=x.off.median(); h=np.where(x.off<=med,1,2); d=line(v,h)
    return dict(line=nm,n=d['n'],games=x.ev.nunique(),per10=round(d['per10'],3),t=round(d['t'],2),h1=round(d['h1'],3),h2=round(d['h2'],3),
                n1=d['n1'],n2=d['n2'],won=round(x.won.mean(),3),imp=round((1/x.px).mean(),3),PASS=d['PASS'])
o=[];r=[]
for mk in MKTS:
    R=T[(T.kind=='ROUND')&(T.mkt==mk)]; N=T[(T.kind=='NEAR')&(T.mkt==mk)]; A=T[(T.kind=='ALL')&(T.mkt==mk)]
    o+=[row(f'{mk} ROUND back *',R,'vb'),row(f'{mk} ROUND lay *',R,'vl')]
    r+=[row(f'{mk} NEAR back',N,'vb'),row(f'{mk} NEAR lay',N,'vl'),row(f'{mk} ALL back',A,'vb'),row(f'{mk} ALL lay',A,'vl')]
    for rv in ROUND:
        x=R[R.rnd==rv]
        if len(x)>=30: r+=[row(f'{mk} ROUND {rv} back',x,'vb'),row(f'{mk} ROUND {rv} lay',x,'vl')]
    for y in sorted(R.yr.unique()):
        r+=[row(f'{mk} {y} ROUND back',R[R.yr==y],'vb'),row(f'{mk} {y} ROUND lay',R[R.yr==y],'vl')]
print("== ITEM 482, scored lines marked *\n",pd.DataFrame(o).to_string(index=False))
RR=pd.DataFrame(r); print("\n-- reading lines, cannot pass (top by |t|)\n",RR.reindex(RR.t.abs().sort_values(ascending=False).index).to_string(index=False))
S=[s for s in o if s.get('PASS')]
print("\n== SURVIVORS"); print(pd.DataFrame(S).to_string(index=False) if S else "none",flush=True); print(f"total {time.time()-T0:.0f}s")
PY
