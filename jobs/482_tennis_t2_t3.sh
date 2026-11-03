#!/bin/bash
set -o pipefail
# 482 (Finder 2026-11-04, queue item 27): TENNIS T2 AND T3 on ip_tape, sport tennis, MATCH_ODDS, two-runner markets, real touch. Pre price and result as job 456.
# T2 (set-1 comeback): favourite 1.30-2.00 before the off; back at the first OPEN in-play sample with back_px > 2.0 (and <= 15), hold to the result. Same as item 7, more days.
# T3 (break-back), never tested: favourite 1.30-2.00; break = back_px >= 1.20 x its value 1 or 2 samples earlier, in play, with the price before the break at most 15. Back. Exit: first later sample with back_px <= pre-break x 1.05, or 40 samples after entry, at lay_px plus one tick. Fewer than 40 samples left and no recovery = settled at the result.
#   FIRST = first break per market only (one per market, independent). ALLNO = every non-overlapping break, correlated within a market. Only FIRST can pass.
# FILL: worse of the trigger touch and the next sample's touch, less one tick. COST: 2% commission, £10 stake. RESULT: runner with back_px or ltp <= 1.05 in the last 15 min of OPEN samples and the other >= 8. KNOWN is diagnostic; only WORST (unknown = -£10 where the trade reaches settlement) can pass.
# Halves: entry ts median. days_to_300 assumes the data accumulates; ip_tape actually rolls at about 6 days (checked 3 Nov), so that column is only meaningful once retention is raised.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,time,warnings,psycopg2,pandas as pd,numpy as np
from collections import defaultdict
from functools import lru_cache
warnings.filterwarnings('ignore')
pd.set_option('display.width',230); pd.set_option('display.max_rows',60); pd.set_option('display.max_columns',30)
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
LAD=[]
for lo,hi,st in ((1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)):
    x=lo
    while x<hi-1e-9: LAD.append(round(x,2)); x+=st
LAD.append(1000.0); LADA=np.array(LAD)
@lru_cache(maxsize=None)
def dn(p): return float(LADA[max(int(np.searchsorted(LADA,round(p,2)-1e-9))-1,0)])
@lru_cache(maxsize=None)
def up(p): return float(LADA[min(int(np.searchsorted(LADA,round(p,2)-1e-9))+1,len(LADA)-1)])
def pnl(p,q,won):
    a=dn(p)
    if a<=1.01: return None
    r=(10*(a-1) if won else -10.0) if q is None else 10*(a/up(q)-1)
    return r*0.98 if r>0 else r
def find_break(b,start=0):
    """First k>=max(start,1) with b[k] >= 1.20*b[k-j], j in 1,2, k-j >= start. Returns (k, pre-break price) or None."""
    for k in range(max(start,1),len(b)):
        for j in (1,2):
            if k-j>=start and b[k]>=1.20*b[k-j]-1e-9 and b[k-j]<=15: return k,b[k-j]
    return None
def t3_exit(b,k,pre,horizon=40):
    """Exit index after entry at k. Recovery first, else k+horizon. None = fewer samples left and no recovery: settle at the result."""
    for i in range(k+1,min(k+horizon,len(b)-1)+1):
        if b[i]<=pre*1.05+1e-9: return i
    return k+horizon if k+horizon<len(b) else None
# known answers, worked by hand
assert dn(2.2)==2.18 and up(2.0)==2.02
assert abs(pnl(2.2,None,True)-10*1.18*0.98)<1e-9 and pnl(2.2,None,False)==-10.0 and pnl(1.02,None,True) is None
assert abs(pnl(2.5,2.0,False)-10*(2.48/2.02-1)*0.98)<1e-9 and abs(pnl(2.1,3.0,True)-10*(2.08/3.05-1))<1e-9
assert find_break([1.5,1.6,1.8])==(2,1.5) and find_break([1.5,1.8])==(1,1.5) and find_break([1.5,1.79]) is None     # 1.8 is exactly 20% up
assert find_break([1.5,1.55,1.6,1.7,1.75]) is None                                                                  # slow drift is not a break
assert find_break([1.5,1.8,1.5,1.8],start=2)==(3,1.5)
assert t3_exit([1.5,1.8,1.7,1.57],1,1.5)==3 and t3_exit([1.5,1.8,1.7],1,1.5) is None and t3_exit([1.5]+[1.8]*42,1,1.5)==41
print("known-answer checks: OK",flush=True)
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
t0=time.time(); fr=[]; day=pd.Timestamp('2026-10-20',tz='UTC'); end=pd.Timestamp.now(tz='UTC')+pd.Timedelta(days=1)
while day<end:
    d=pd.read_sql("""SELECT market_id,event_name,ts,secs_since_start s,status,sel_id,back_px::float bp,back_sz::float bs,lay_px::float lp,ltp::float ltp FROM ip_tape
      WHERE sport='tennis' AND ts>=%s AND ts<%s AND market_type='MATCH_ODDS'""",con,params=(day,day+pd.Timedelta(days=1)))
    if len(d): fr.append(d)
    print(f"  {day.date()} rows {len(d)} | {int(time.time()-t0)}s",flush=True); day+=pd.Timedelta(days=1)
if not fr: print("ERROR: no tennis rows pulled, so no verdict"); sys.exit(1)
T=pd.concat(fr,ignore_index=True).sort_values(['market_id','ts'])
print(f"rows {len(T)} | markets {T.market_id.nunique()} | {T.ts.min()} .. {T.ts.max()}",flush=True)
gap=T.groupby(['market_id','sel_id']).ts.diff().dt.total_seconds(); print(f"sample gap per runner (s): median {gap.median():.0f}, p90 {gap.quantile(.9):.0f}",flush=True)
SK=defaultdict(int); rows=[]
for mid,g in T.groupby('market_id',sort=False):
    sels=g.sel_id.unique()
    if len(sels)!=2: SK['not 2 runners']+=1; continue
    ok=g[(g.status=='OPEN')&g.bp.notna()&(g.bs>0)&g.lp.notna()]
    pre=ok[ok.s<=0]
    if pre.groupby('sel_id').size().size<2: pre=ok[(ok.s>0)&(ok.s<=600)]
    if pre.groupby('sel_id').size().size<2: SK['no pre/early price']+=1; continue
    last=pre.sort_values('ts').groupby('sel_id').tail(1).set_index('sel_id').bp; fav=last.idxmin(); p0=last[fav]
    if not 1.30<=p0<=2.00: SK['fav outside band']+=1; continue
    tail=g[(g.status=='OPEN')&(g.ts>=g.ts.max()-pd.Timedelta(minutes=15))]; tail=tail.assign(lo=pd.concat([tail.bp,tail.ltp],axis=1).min(axis=1))
    winner=None
    for s in sels:
        o=[x for x in sels if x!=s][0]
        if (tail[tail.sel_id==s].lo<=1.05).any() and (tail[tail.sel_id==o].bp>=8).any(): winner=s
    f=ok[(ok.sel_id==fav)&(ok.s>pre.s.max())].sort_values('ts')
    if len(f)<3: SK['under 3 in-play samples']+=1; continue
    b=f.bp.values; l=f.lp.values; ts=f.ts.values; known=winner is not None; won=winner==fav
    hit=np.where((b>2.0)&(b<=15))[0]
    if len(hit):
        k=int(hit[0]); fp=min(b[k],b[k+1]) if k+1<len(b) else b[k]; r=pnl(fp,None,won)
        if r is not None: rows.append(dict(rule='T2',set='FIRST',mid=mid,ts=ts[k],known=known,pnl=r,settled=True,p0=p0,entry=fp,won=won))
        r=pnl(b[k],None,won)   # trigger-touch fill as job 456: no latency, for comparison with item 7; diagnostic, kept out of the pass test by set='TOUCH'
        if r is not None: rows.append(dict(rule='T2',set='TOUCH',mid=mid,ts=ts[k],known=known,pnl=r,settled=True,p0=p0,entry=b[k],won=won))
    start=0; nth=0
    while True:
        br=find_break(b,start)
        if br is None: break
        k,prep=br; e=t3_exit(b,k,prep); fp=min(b[k],b[k+1]) if k+1<len(b) else b[k]
        r=pnl(fp,None if e is None else l[e],won)
        if r is not None:
            for st_ in (('FIRST','ALLNO') if nth==0 else ('ALLNO',)):
                rows.append(dict(rule='T3',set=st_,mid=mid,ts=ts[k],known=known,pnl=r,settled=e is None,p0=p0,entry=fp,won=won))
            if nth==0:
                r2=pnl(b[k],None if e is None else l[e],won)
                if r2 is not None: rows.append(dict(rule='T3',set='TOUCH',mid=mid,ts=ts[k],known=known,pnl=r2,settled=e is None,p0=p0,entry=b[k],won=won))
        nth+=1
        if e is None: break
        start=e+1
print("skips:",dict(SK),flush=True)
R=pd.DataFrame(rows)
if R.empty: print("ERROR: no entries, so no verdict"); sys.exit(1)
R['worst']=np.where(R.settled&~R.known,-10.0,R.pnl)
md=R.ts.median(); days=max((pd.Timestamp(T.ts.max())-pd.Timestamp(T.ts.min())).total_seconds()/86400,0.1)
def tstat(v): return v.mean()/(v.std(ddof=1)/np.sqrt(len(v))) if len(v)>1 and v.std(ddof=1)>0 else 0.0
out=[]
for (rule,st_),d in R.groupby(['rule','set']):
    a=d[d.ts<md].worst; c=d[d.ts>=md].worst; kn=d[d.known|~d.settled].pnl
    out.append(dict(rule=rule,set=st_,n=len(d),markets=d.mid.nunique(),worst=d.worst.mean(),t=tstat(d.worst),n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(c),h2=c.mean() if len(c) else np.nan,known=kn.mean(),n_known=len(kn),exit_print=(~d.settled).mean(),fav_won=d[d.known].won.mean(),avg_entry=d.entry.mean(),
       per_day=round(len(d)/days,1),days_to_300=round(max(0,300-len(d))/max(len(d)/days,0.01),1),PASS=st_=='FIRST' and len(d)>=300 and len(a)>=150 and len(c)>=150 and tstat(d.worst)>=3.5 and a.mean()>0 and c.mean()>0 and d.worst.mean()>=0.15))
S=pd.DataFrame(out); print("\n== RESULTS per £10 (worst = unknown result at settlement is -£10)\n",S.round(3).to_string(index=False))
B=[]
for (rule,st_,pb),d in R[R.set=='FIRST'].assign(pb=pd.cut(R[R.set=='FIRST'].p0,[1.29,1.5,1.7,2.0]).astype(str)).groupby(['rule','set','pb']):
    a=d[d.ts<md].worst; c=d[d.ts>=md].worst
    B.append(dict(rule=rule,band=pb,n=len(d),worst=d.worst.mean(),t=tstat(d.worst),h1=a.mean() if len(a) else np.nan,h2=c.mean() if len(c) else np.nan))
print("\n== by pre-match favourite band\n",pd.DataFrame(B).round(3).to_string(index=False))
W=S[S.PASS==True]; print(f"\n== SURVIVORS: {len(W)}"); print(W.round(3).to_string(index=False) if len(W) else "none")
PY
