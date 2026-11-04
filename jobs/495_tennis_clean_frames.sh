#!/bin/bash
set -o pipefail
# 495 (Finder 2026-11-04, queue item 44, tennis slice only, cut to fit the night's time left): TENNIS T2 AND T3 on ip_tape WITHOUT REPLAYED FRAMES. Triggers, fills, costs and results exactly as job 482; RAW repeats 482's method on what the table holds now, CLEAN drops replays first.
# REPLAY: a frame whose total_matched is below the running max of earlier frames in that market (job 487's definition, past data only, so a live bot could do the same). NULL total_matched cannot be judged: kept, counted. Replays are dropped before the pre price, the trigger, the exit and the result are read.
# ONLY CLEAN x FIRST can pass (one per market). lost = RAW FIRST markets with no CLEAN FIRST entry; new = the reverse. Unknown result at settlement = -£10. Halves: entry ts median within each mode. Racing, basketball and the momentum test (458) are NOT in this job.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
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
    for k in range(max(start,1),len(b)):
        for j in (1,2):
            if k-j>=start and b[k]>=1.20*b[k-j]-1e-9 and b[k-j]<=15: return k,b[k-j]
    return None
def t3_exit(b,k,pre,horizon=40):
    for i in range(k+1,min(k+horizon,len(b)-1)+1):
        if b[i]<=pre*1.05+1e-9: return i
    return k+horizon if k+horizon<len(b) else None
def clean_mask(tm):
    """True where total_matched is not below the running max of earlier frames; NULL is kept and does not move the max."""
    tm=np.asarray(tm,dtype=float); out=np.ones(len(tm),dtype=bool); mx=-np.inf
    for i,v in enumerate(tm):
        if np.isnan(v): continue
        if v<mx: out[i]=False
        else: mx=v
    return out
def tstat(v):
    v=np.asarray(v,dtype=float)
    if len(v)<2: return 0.0
    s=v.std(ddof=1); return float(v.mean()/(s/len(v)**0.5)) if s>0 else 0.0
# known answers, worked by hand; the first group is job 482's
assert dn(2.2)==2.18 and up(2.0)==2.02
assert abs(pnl(2.2,None,True)-10*1.18*0.98)<1e-9 and pnl(2.2,None,False)==-10.0 and pnl(1.02,None,True) is None
assert abs(pnl(2.5,2.0,False)-10*(2.48/2.02-1)*0.98)<1e-9 and abs(pnl(2.1,3.0,True)-10*(2.08/3.05-1))<1e-9
assert find_break([1.5,1.6,1.8])==(2,1.5) and find_break([1.5,1.79]) is None and find_break([1.5,1.55,1.6,1.7,1.75]) is None
assert t3_exit([1.5,1.8,1.7,1.57],1,1.5)==3 and t3_exit([1.5,1.8,1.7],1,1.5) is None and t3_exit([1.5]+[1.8]*42,1,1.5)==41
assert clean_mask([10,12,11,12,13,12.5]).tolist()==[True,True,False,True,True,False]      # 11 and 12.5 are replays; an equal 12 stays
assert clean_mask([10,float('nan'),9,11]).tolist()==[True,True,False,True]                # NULL kept, and does not reset the max
_b=np.array([1.5,1.5,1.9,1.9,1.5]); _m=clean_mask([100,110,90,90,120])                    # a 1.9 jump on replayed frames: a false break on RAW, none on CLEAN
assert find_break(_b.tolist())==(2,1.5) and find_break(_b[_m].tolist()) is None
assert abs(tstat([1,3])-2.0)<1e-9
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)

con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'; SET max_parallel_workers_per_gather=0")
cur.execute("SELECT column_name FROM information_schema.columns WHERE table_name='ip_tape' ORDER BY ordinal_position"); cols=[r[0] for r in cur.fetchall()]; print("ip_tape columns:",cols,flush=True)
t0=time.time(); fr=[]; day=pd.Timestamp('2026-10-20',tz='UTC'); end=pd.Timestamp.now(tz='UTC')+pd.Timedelta(days=1)
while day<end:
    cur.execute("""SELECT market_id,ts,secs_since_start,status,sel_id,back_px::float8,back_sz::float8,lay_px::float8,ltp::float8,total_matched::float8 FROM ip_tape
      WHERE sport='tennis' AND ts>=%s AND ts<%s AND market_type='MATCH_ODDS'""",(day,day+pd.Timedelta(days=1)))
    d=pd.DataFrame(cur.fetchall(),columns=['market_id','ts','s','status','sel_id','bp','bs','lp','ltp','tm'])
    if len(d): fr.append(d)
    print(f"  {day.date()} rows {len(d)} | {int(time.time()-t0)}s",flush=True); day+=pd.Timedelta(days=1)
con.close()
if not fr: print("ERROR: no tennis rows pulled, so no verdict"); sys.exit(1)
T=pd.concat(fr,ignore_index=True).sort_values(['market_id','ts'],kind='stable')
for c in ('s','bp','bs','lp','ltp','tm'): T[c]=pd.to_numeric(T[c],errors='coerce')
# frame = market_id + ts; runners of one frame share total_matched, so judge per row in time order: ties keep
T['clean']=np.concatenate([clean_mask(g.tm.values) for _,g in T.groupby('market_id',sort=False)])
print(f"rows {len(T)} | markets {T.market_id.nunique()} | {T.ts.min()} .. {T.ts.max()} | tm null {T.tm.isna().mean():.1%} | replay rows {(~T.clean).mean():.1%}, OPEN only {(~T[T.status=='OPEN'].clean).mean():.1%}",flush=True)
_r=T.groupby('market_id').clean.apply(lambda x:(~x).mean()); print("replay share per market, quantiles:",_r.quantile([.25,.5,.75,.9,.99]).round(3).to_dict(),f"| markets with none {(_r==0).mean():.1%}",flush=True)
_h=T.assign(day=pd.to_datetime(T.ts,utc=True).dt.date).groupby('day').clean.apply(lambda x:round(float((~x).mean()),3)); print("replay share by day:",{str(k):v for k,v in _h.items()},flush=True)
def run(T,lab):
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
        for s_ in sels:
            o=[x for x in sels if x!=s_][0]
            if (tail[tail.sel_id==s_].lo<=1.05).any() and (tail[tail.sel_id==o].bp>=8).any(): winner=s_
        f=ok[(ok.sel_id==fav)&(ok.s>pre.s.max())].sort_values('ts')
        if len(f)<3: SK['under 3 in-play samples']+=1; continue
        b=f.bp.values; l=f.lp.values; ts=f.ts.values; known=winner is not None; won=winner==fav
        hit=np.where((b>2.0)&(b<=15))[0]
        if len(hit):
            k=int(hit[0]); fp=min(b[k],b[k+1]) if k+1<len(b) else b[k]; r=pnl(fp,None,won)
            if r is not None: rows.append(dict(rule='T2',set='FIRST',mid=mid,ts=ts[k],known=known,pnl=r,settled=True,won=won))
        start=0; nth=0
        while True:
            br=find_break(b.tolist(),start)
            if br is None: break
            k,prep=br; e=t3_exit(b,k,prep); fp=min(b[k],b[k+1]) if k+1<len(b) else b[k]
            r=pnl(fp,None if e is None else l[e],won)
            if r is not None:
                for st_ in (('FIRST','ALLNO') if nth==0 else ('ALLNO',)):
                    rows.append(dict(rule='T3',set=st_,mid=mid,ts=ts[k],known=known,pnl=r,settled=e is None,won=won))
            nth+=1
            if e is None: break
            start=e+1
    print(f"{lab} skips:",dict(SK),flush=True)
    R=pd.DataFrame(rows)
    if R.empty: return R
    R['worst']=np.where(R.settled&~R.known,-10.0,R.pnl); R['mode']=lab
    return R
RR=run(T,'RAW'); RC=run(T[T.clean],'CLEAN')
if RR.empty or RC.empty: print("ERROR: no entries in one mode, so no verdict"); sys.exit(1)
out=[]
for R,lab in ((RR,'RAW'),(RC,'CLEAN')):
    md=pd.Series(R.ts).median()
    for (rule,st_),d in R.groupby(['rule','set']):
        a=d[d.ts<md].worst; c=d[d.ts>=md].worst; kn=d[d.known|~d.settled].pnl
        out.append(dict(mode=lab,rule=rule,set=st_,n=len(d),markets=d.mid.nunique(),worst=d.worst.mean(),t=tstat(d.worst),n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(c),h2=c.mean() if len(c) else np.nan,known=kn.mean(),n_known=len(kn),exit_print=(~d.settled).mean(),fav_won=d[d.known].won.mean(),
            PASS=lab=='CLEAN' and st_=='FIRST' and len(d)>=300 and len(a)>=150 and len(c)>=150 and tstat(d.worst)>=3.5 and a.mean()>0 and c.mean()>0 and d.worst.mean()>=0.15))
S=pd.DataFrame(out); print("\n== RESULTS per £10 (worst = unknown result at settlement is -£10)\n",S.round(3).to_string(index=False))
for rule in ('T2','T3'):
    a=set(RR[(RR.rule==rule)&(RR.set=='FIRST')].mid); b=set(RC[(RC.rule==rule)&(RC.set=='FIRST')].mid)
    print(f"{rule} FIRST triggers: RAW {len(a)}, CLEAN {len(b)}, lost {len(a-b)}, new {len(b-a)}, common {len(a&b)}",flush=True)
_a=RR[RR.set=='ALLNO']; _b=RC[RC.set=='ALLNO']; print(f"T3 ALLNO entries per market: RAW {len(_a)/max(_a.mid.nunique(),1):.2f}, CLEAN {len(_b)/max(_b.mid.nunique(),1):.2f}",flush=True)
W=S[S.PASS==True]; print(f"\n== SURVIVORS: {len(W)} of 2 eligible lines (CLEAN FIRST)"); print(W.round(3).to_string(index=False) if len(W) else "none")
PY
