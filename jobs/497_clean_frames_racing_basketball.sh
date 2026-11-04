#!/bin/bash
set -o pipefail
# 497 (Finder 2026-11-04, queue item 48): CLEAN-FRAME RE-RUN of racing shortened 15/25% (job 481, ip_tape WIN) and the momentum test (job 458, basketball MO). Last 3 days only, newest first, as the item allows; coverage printed. Tennis was job 495.
# FIRST QUESTION: can runners in one market and ts carry different total_matched? Printed. Replay is judged PER FRAME: frame tm = max of its rows; a frame is a replay if its tm is below the running max of EARLIER frames (past data only). NULL tm kept, does not move the max. Replays are dropped before the off price, triggers, fills, exits and results are read.
# RACING as 481: off = first in-play snapshot, trigger = back_px <= off x (1-X), result = single runner <= 1.05 on the last OPEN snapshot, unknown = -£10 (worst). Fill NEXT = next snapshot's touch, one tick adverse (the only fill that can pass; none = trigger touch). Fill WORSE = 481's fill, for comparison: it looks ahead against the trader. FIRST = first runner to trigger in the race.
# MOMENTUM as 458: first snapshot k>=20 where back_px <= 0.85 x back_px at k-20; back there, exit at k+20 at lay_px (next snapshot with one; none = settle). Snapshot counts shrink when replays go, so CLEAN windows span more real time. FIRST = first runner per market. Entry at the trigger snapshot's touch as 458, so it needs a next-print check before any stake.
# COST: one tick adverse, 2% commission, £10 risk. Only CLEAN x FIRST x (NEXT for racing) x worst can pass. Halves: median entry time within the line.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,warnings,psycopg2,pandas as pd,numpy as np
from collections import defaultdict
from functools import lru_cache
warnings.filterwarnings('ignore')
pd.set_option('display.width',230); pd.set_option('display.max_rows',80); pd.set_option('display.max_columns',30)
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
def comm(x): return x*0.98 if x>0 else x
def back_settle(p,won):
    a=dn(p)
    if a<=1.01: return np.nan
    return comm(10*(a-1)) if won else -10.0
def lay_settle(p,won):
    a=up(p); return -10.0 if won else comm(10/(a-1))
def back_exit(p,q):
    a=dn(p)
    return np.nan if a<=1.01 else comm(10*(a/up(q)-1))
def trigger(ser,x):
    off=ser[0]
    for i in range(1,len(ser)):
        if ser[i]<=off*(1-x)+1e-9: return i
    return None
def winner(last):
    w=[k for k,v in last.items() if v is not None and v<=1.05]
    return w[0] if len(w)==1 else None
def mom_trigger(bp,back=20,x=0.15):
    for k in range(back,len(bp)):
        a,b=bp[k-back],bp[k]
        if np.isfinite(a) and np.isfinite(b) and b<=a*(1-x)+1e-9 and b<=50: return k
    return None
def clean_mask(tm):
    tm=np.asarray(tm,dtype=float); out=np.ones(len(tm),dtype=bool); mx=-np.inf
    for i,v in enumerate(tm):
        if np.isnan(v): continue
        if v<mx: out[i]=False
        else: mx=v
    return out
def frame_clean(d):
    """d: market_id, ts, tm. Boolean per row: its frame is not a replay."""
    f=d.groupby(['market_id','ts'],sort=True).tm.max().reset_index()
    f['ok']=np.concatenate([clean_mask(g.tm.values) for _,g in f.groupby('market_id',sort=False)])
    return d[['market_id','ts']].merge(f[['market_id','ts','ok']],on=['market_id','ts'],how='left').ok.values
def tstat(v):
    v=np.asarray(v,dtype=float); v=v[np.isfinite(v)]
    if len(v)<2: return 0.0
    s=v.std(ddof=1); return float(v.mean()/(s/len(v)**0.5)) if s>0 else 0.0
# known answers, worked by hand
assert dn(3.05)==3.0 and up(2.0)==2.02 and dn(2.0)==1.99
assert abs(back_settle(3.05,True)-10*2.0*0.98)<1e-9 and back_settle(3.0,False)==-10.0 and np.isnan(back_settle(1.02,True))     # 1.02 fills 1.01: no bet
assert abs(lay_settle(4.9,False)-10/4.0*0.98)<1e-9 and lay_settle(2.0,True)==-10.0                                              # 4.9 fills 5.0
assert abs(back_exit(2.5,2.0)-10*(2.48/2.02-1)*0.98)<1e-9 and abs(back_exit(2.1,3.0)-10*(2.08/3.05-1))<1e-9                     # profit less 2%; a loss, no commission
assert trigger([10.0,9.0,8.5,7.0],0.15)==2 and trigger([10.0,9.0,8.5,7.0],0.25)==3 and trigger([10.0,9.0],0.25) is None and trigger([10.0],0.15) is None   # 8.5 is exactly 15% down
assert winner({'a':1.03,'b':40.0})=='a' and winner({'a':1.03,'b':1.04}) is None and winner({'a':None,'b':1.05})=='b'
assert mom_trigger([2.0]*20+[1.7])==20 and mom_trigger([2.0]*20+[1.71]) is None and mom_trigger([2.0]*19+[1.0]) is None and mom_trigger([np.nan]*20+[1.0]) is None
assert clean_mask([10,12,11,12,13,12.5]).tolist()==[True,True,False,True,True,False] and clean_mask([10,float('nan'),9,11]).tolist()==[True,True,False,True]
_d=pd.DataFrame(dict(market_id=['m']*6+['n'],ts=[1,1,2,2,3,3,1],tm=[100.,90.,120.,120.,110.,110.,5.]))      # frame 1 has two tm values: judged at 100, kept, both rows. frame 3 at 110 is below 120: replay. market n starts its own max
assert frame_clean(_d).tolist()==[True,True,True,True,False,False,True]
_d2=pd.DataFrame(dict(market_id=['m','m','m'],ts=[1,2,3],tm=[100.,np.nan,90.])); assert frame_clean(_d2).tolist()==[True,True,False]   # all-NULL frame kept, no reset
assert abs(tstat([1,3])-2.0)<1e-9
print("known-answer checks: OK",flush=True)

def racing(A,lab):
    SK=defaultdict(int); rows=[]
    for mid,g in A.groupby('market_id',sort=False):
        tss=np.sort(g.ts.unique()); tidx={t:i for i,t in enumerate(tss)}
        if len(tss)<3: SK['under 3 snapshots']+=1; continue
        la=g[g.ts==tss[-1]]; last={r.sel_id:(r.bp if pd.notna(r.bp) and r.bp>1 else (r.ltp if pd.notna(r.ltp) else None)) for r in la.itertuples()}
        win=winner(last); SK['clean single winner' if win is not None else 'unknown winner']+=1
        two=g[(g.bp>1)&(g.lp>1)&(g.lp<1000)]; tr=[]
        for sid,s in two.groupby('sel_id',sort=False):
            if s.ts.iloc[0]!=tss[0]: continue
            b=s.bp.values.astype(float); l=s.lp.values.astype(float); tt=s.ts.values
            if b[0]>50: SK['off over 50']+=1; continue
            for x,xl in ((0.15,'15%'),(0.25,'25%')):
                i=trigger(b,x)
                if i is None: continue
                ni=min(i+1,len(b)-1)
                tr.append(dict(x=xl,k=tidx[tt[i]],ts=tt[i],sid=sid,bn=b[ni],ln=l[ni],bw=min(b[i],b[ni]),lw=max(l[i],l[ni])))
        for xl in ('15%','25%'):
            for j,t in enumerate(sorted([t for t in tr if t['x']==xl],key=lambda t:t['k'])):
                w=None if win is None else t['sid']==win
                for side,fill,v in (('BACK','NEXT',t['bn']),('BACK','WORSE',t['bw']),('LAY','NEXT',t['ln']),('LAY','WORSE',t['lw'])):
                    f=back_settle if side=='BACK' else lay_settle
                    rows.append(dict(mode=lab,rule=f'race {xl} {side}',fill=fill,mid=mid,ts=t['ts'],first=j==0,known=win is not None,worst=(f(v,w) if w is not None else -10.0),pnl=(f(v,w) if w is not None else np.nan)))
    print(f"{lab} racing:",dict(SK),flush=True)
    return rows
def momentum(T,lab):
    SK=defaultdict(int); rows=[]
    for mid,g in T.groupby('market_id',sort=False):
        ts=np.sort(g.ts.unique())
        if len(ts)<8: SK['under 8 snapshots']+=1; continue
        last=g[g.ts==ts[-1]]; lo=last[['bp','ltp']].min(axis=1); w=last.sel_id[lo<=1.05].unique(); win=w[0] if len(w)==1 else None
        SK['inferable' if win is not None else 'unknown']+=1; tr=[]
        for s,d in g.groupby('sel_id',sort=False):
            d=d.drop_duplicates('ts').set_index('ts').reindex(ts)
            bp=d.bp.where(d.bs>0).values.astype(float); lp=d.lp.where(d.ls>0).values.astype(float)
            k=mom_trigger(bp)
            if k is None: continue
            xi=[i for i in range(k+20,len(ts)) if np.isfinite(lp[i])]
            res=None if win is None else s==win
            if xi: r=back_exit(bp[k],lp[xi[0]]); wr=r
            else: r=back_settle(bp[k],res) if res is not None else np.nan; wr=r if res is not None else -10.0
            tr.append((k,ts[k],r,wr,bool(xi) or res is not None))
        for j,(k,t,r,wr,kn) in enumerate(sorted(tr,key=lambda z:z[0])):
            rows.append(dict(mode=lab,rule='basketball momentum',fill='TOUCH',mid=mid,ts=t,first=j==0,known=kn,worst=wr,pnl=r))
    print(f"{lab} momentum:",dict(SK),flush=True)
    return rows

# end-to-end on tiny frames, worked by hand. ts are integers, as in the run
_n=4; _A=pd.DataFrame(dict(market_id=['m']*8,ts=[1,2,3,4]*2,sel_id=['a']*_n+['b']*_n,bp=[10.,8.,7.,1.03,5.,6.,7.,40.],lp=[11.,8.2,7.2,1.04,5.2,6.2,7.2,50.],ltp=[10.,8.,7.,1.03,5.,6.,7.,40.]))
_x=pd.DataFrame(racing(_A,'T')); _y=_x[(_x.rule=='race 15% BACK')&(_x.fill=='NEXT')]
assert len(_y)==1 and abs(_y.worst.iloc[0]-10*5.8*0.98)<1e-9 and bool(_y['first'].iloc[0])      # trigger 8.0 on a, next print 7.0 fills 6.8, a won
_y=_x[(_x.rule=='race 15% LAY')&(_x.fill=='WORSE')]; assert len(_y)==1 and _y.worst.iloc[0]==-10.0
_M=pd.DataFrame(dict(market_id=['k']*90,ts=list(range(45))*2,sel_id=['a']*45+['b']*45,bp=[2.0]*20+[1.7]*25+[3.0]*45,bs=[5.]*90,lp=[2.02]*40+[1.5]*5+[3.05]*45,ls=[5.]*90,ltp=[2.0]*90))
_z=pd.DataFrame(momentum(_M,'T')); assert len(_z)==1 and abs(_z.worst.iloc[0]-10*(1.69/1.51-1)*0.98)<1e-9   # trigger k=20 at 1.7 fills 1.69; exit k=40 lay 1.5, one tick up 1.51
print("end-to-end checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)

BUDGET=1700
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'; SET max_parallel_workers_per_gather=0")
t0=time.time(); now=pd.Timestamp.now(tz='UTC'); COV={}
def fetch(sports,mts,label,stop):
    fr=[]; b=now.floor('6h')+pd.Timedelta(hours=6); oldest=now-pd.Timedelta(days=3); done=None
    while b>oldest:
        if time.time()-t0>stop: print(f"  {label}: time budget reached, stopped at {done}",flush=True); break
        a=b-pd.Timedelta(hours=6)
        cur.execute("""SELECT market_id,ts,sel_id,back_px::float8,back_sz::float8,lay_px::float8,lay_sz::float8,ltp::float8,total_matched::float8 FROM ip_tape
          WHERE sport=ANY(%s) AND market_type=ANY(%s) AND status='OPEN' AND secs_since_start>0 AND ts>=%s AND ts<%s""",(sports,mts,a,b))
        d=pd.DataFrame(cur.fetchall(),columns=['market_id','ts','sel_id','bp','bs','lp','ls','ltp','tm'])
        if len(d): fr.append(d)
        done=a; print(f"  {label} {a}: rows {len(d)} | {int(time.time()-t0)}s",flush=True); b=a
    COV[label]=str(done)
    return pd.concat(fr,ignore_index=True) if fr else pd.DataFrame()
A=fetch(['Horse Racing','horse_racing','7','Horse racing'],['WIN'],'racing',1000)
B=fetch(['basketball','Basketball','7522'],['MATCH_ODDS','MONEY_LINE'],'basketball',BUDGET)
A.to_pickle('/tmp/497_racing.pkl'); B.to_pickle('/tmp/497_basketball.pkl')
con.close(); print("coverage back to:",COV,"| fetch",int(time.time()-t0),"s",flush=True)
rows=[]
for lab,D,fn in (('racing',A,racing),('basketball',B,momentum)):
    if D.empty: print(f"== {lab}: NO ROWS, not tested",flush=True); continue
    for c in ('bp','bs','lp','ls','ltp','tm'): D[c]=pd.to_numeric(D[c],errors='coerce')
    D['ts']=pd.to_datetime(D.ts,utc=True); D=D.sort_values(['market_id','ts'],kind='stable').reset_index(drop=True); _rng=(D.ts.min(),D.ts.max()); D['ts']=D.ts.dt.tz_localize(None).astype('datetime64[ns]').astype('int64')
    nt=D.groupby(['market_id','ts']).tm.nunique()
    D['ok']=frame_clean(D); D['row_ok']=np.concatenate([clean_mask(g.tm.values) for _,g in D.groupby('market_id',sort=False)])
    fr=D.drop_duplicates(['market_id','ts'])
    print(f"== {lab}: rows {len(D)}, markets {D.market_id.nunique()}, {_rng[0]} .. {_rng[1]}, tm null {D.tm.isna().mean():.1%}",flush=True)
    print(f"   frames with more than one total_matched: {(nt>1).mean():.2%} of {len(nt)} | replay share: per row {(~D.row_ok).mean():.1%}, rows in replay frames {(~D.ok).mean():.1%}, per frame {(~fr.ok).mean():.1%}",flush=True)
    _r=D.groupby('market_id').ok.apply(lambda x:(~x).mean()); print("   replay share per market, quantiles:",_r.quantile([.25,.5,.75,.9]).round(3).to_dict(),f"| markets with none {(_r==0).mean():.1%}",flush=True)
    rows+=fn(D,'RAW'); rows+=fn(D[D.ok],'CLEAN')
R=pd.DataFrame(rows)
if R.empty: print("ERROR: no entries, so no verdict"); sys.exit(1)
out=[]
for (m,rule,fill,first),d in pd.concat([R.assign(set='ALL'),R[R['first']].assign(set='FIRST')]).groupby(['mode','rule','fill','set']):
    d=d[np.isfinite(d.worst)]; md=d.ts.median(); a=d[d.ts<md].worst; b=d[d.ts>=md].worst; kn=d.pnl.dropna()
    el=m=='CLEAN' and first=='FIRST' and fill in ('NEXT','TOUCH')
    out.append(dict(mode=m,rule=rule,fill=fill,set=first,n=len(d),markets=d.mid.nunique(),worst=d.worst.mean(),t=tstat(d.worst),n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,known=kn.mean() if len(kn) else np.nan,n_known=len(kn),ELIG=el,
        PASS=el and len(d)>=300 and len(a)>=150 and len(b)>=150 and tstat(d.worst)>=3.5 and a.mean()>0 and b.mean()>0 and d.worst.mean()>=0.15))
S=pd.DataFrame(out); print("\n== RESULTS per £10 (worst = unknown result is -£10; known = diagnostic)\n",S.sort_values('t',ascending=False).drop(columns=['PASS']).round(3).to_string(index=False))
for rule,fill in R[['rule','fill']].drop_duplicates().itertuples(index=False):
    if fill=='WORSE': continue
    x=R[(R.rule==rule)&(R.fill==fill)&R['first']]; a=set(x[x['mode']=='RAW'].mid); b=set(x[x['mode']=='CLEAN'].mid)
    y=R[(R.rule==rule)&(R.fill==fill)]; ra=y[y['mode']=='RAW']; rc=y[y['mode']=='CLEAN']
    print(f"{rule}: FIRST triggers RAW {len(a)}, CLEAN {len(b)}, lost {len(a-b)}, new {len(b-a)}, common {len(a&b)} | entries per market RAW {len(ra)/max(ra.mid.nunique(),1):.2f}, CLEAN {len(rc)/max(rc.mid.nunique(),1):.2f}",flush=True)
W=S[S.PASS==True]; print(f"\n== SURVIVORS: {len(W)} of {int(S.ELIG.sum())} eligible lines (CLEAN, FIRST, next-print or 458's touch, worst)"); print(W.drop(columns=['PASS','ELIG']).round(3).to_string(index=False) if len(W) else "none")
PY
