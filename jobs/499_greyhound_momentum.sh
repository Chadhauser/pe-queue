#!/bin/bash
set -o pipefail
# 499_greyhound_momentum (Finder 2026-11-04, queue item 58): trade closed before the off, so no result needed. The number 499 is reused with a new slug: 450-499 are all taken.
# SIGNAL: a runner's first pair of consecutive pre-off prints moving >= 10% (shorten: ratio <= 0.90; drift: ratio >= 1.10). One entry per runner.
# ENTRY: the next real print, one tick adverse. EXIT: the last pre-off print, one tick adverse. No forward-fill. 2% commission on profit. Back stake 10, lay liability 10.
# SIDES: BACK_SHORT and LAY_DRIFT follow the move; LAY_SHORT and BACK_DRIFT are the mirror.
# NO EXIT: if the entry print is the runner's last, a live trader would be holding into the race and the tape has no result (item 46). The strict line cannot price it; `scr` scores those entries as a scratch at the entry print, cost only, so that dropping them cannot flatter a line.
# CONTROL: runners with >= 3 prints and no signal, entered at their second print and held to the last. Not gated.
# FIX 2026-11-04 (the one allowed re-run): the first run read pandas microsecond timestamps as nanoseconds, so every minute figure was 1000x too small, every entry fell in the <2m band and dates printed as 1970. Times are now float minutes from the epoch, with a known-answer check at both units.
# SAMPLE: all markets in shuffled order, stopping at a time budget, so a cut sample is not biased by date.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,time,random,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
pd.set_option('display.width',240); pd.set_option('display.max_rows',300); pd.set_option('display.max_columns',30)
T0=time.time(); BUDGET=2300
LD=[]
for lo,hi,st in ((1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)):
    v=lo
    while v<hi-1e-9: LD.append(round(v,2)); v+=st
LD.append(1000.0); LD=np.array(LD)
def ix(p): return int(np.searchsorted(LD,round(float(p),2)-1e-9))
def step(p,k): return float(LD[min(max(ix(p)+k,0),len(LD)-1)])
def net(x): return x*0.98 if x>0 else x
def back_pl(p,q,k=1):
    a=step(p,-k)
    return None if a<=1.01 else net(10*(a/step(q,k)-1))
def lay_pl(p,q,k=1):
    a=step(p,k)
    return None if a<=1.01 else net(10/(a-1)*(1-a/step(q,-k)))
def first_signal(p,th=0.10):
    for i in range(1,len(p)):
        r=round(p[i]/p[i-1],6)
        if r<=round(1-th,6): return i,'S'
        if r>=round(1+th,6): return i,'D'
    return None,None
def tstat(x):
    x=np.asarray(x,dtype=float); s=x.std(ddof=1) if len(x)>1 else 0
    return x.mean()/(s/len(x)**0.5) if s>0 else 0.0
# known answers, worked by hand
assert step(5.0,-1)==4.9 and step(5.0,1)==5.1 and step(3.0,-1)==2.98 and step(3.0,1)==3.05 and step(1.01,-1)==1.01
assert abs(back_pl(5.0,4.0)-1.912195)<1e-5                  # a 4.9, out 4.1: 10*(4.9/4.1-1)=1.951220, less 2%
assert abs(back_pl(5.0,6.0)-(-2.096774))<1e-5               # a 4.9, out 6.2: loss, no commission
assert abs(lay_pl(5.0,6.0)-0.324100)<1e-5                   # a 5.1, s 10/4.1, out 5.9: s*(1-5.1/5.9)=0.330715, less 2%
assert abs(lay_pl(5.0,4.0)-(10/4.1*(1-5.1/3.95)))<1e-9      # lay loses when it shortens, no commission
assert abs(back_pl(5.0,5.0)-10*(4.9/5.1-1))<1e-9 and lay_pl(5.0,5.0,0)==0.0 and back_pl(1.01,2.0) is None
assert first_signal([5,5,4.5,4.6,4])==(2,'S') and first_signal([5,5.4,5.3])==(None,None) and first_signal([5,5.5])==(1,'D') and first_signal([2.0,1.8])==(1,'S')
EPOCH=pd.Timestamp('1970-01-01',tz='UTC')
def to_min(c): return (pd.to_datetime(c,utc=True)-EPOCH)/pd.Timedelta(minutes=1)
_a=pd.Series(pd.to_datetime(['2025-01-01 00:00:00','2025-01-01 00:10:00'],utc=True))
for _u in ('ns','us','s'):
    _m=to_min(_a.dt.as_unit(_u)); assert abs(_m.iloc[1]-_m.iloc[0]-10)<1e-6 and pd.to_datetime(_m.iloc[0],unit='m',utc=True).year==2025
print("known-answer checks: OK",flush=True)
def sim_runner(mid,mt,ts,p):
    """Returns (trades, flags). p and ts are the runner's pre-off prints in time order."""
    i,kind=first_signal(p)
    if i is None:
        if len(p)>=3:
            return [dict(m=mid,mt=mt,kind='C',side=s,p=p[1],q=p[-1],mins=mt-ts[1],hold=ts[-1]-ts[1],age=mt-ts[-1],r=np.nan,np_=len(p),pl=f(p[1],p[-1]),g=f(p[1],p[-1],0),scr=f(p[1],p[-1]),noexit=False) for s,f in (('CTRL_BACK',back_pl),('CTRL_LAY',lay_pl))],'none'
        return [],'none'
    if i+1>=len(p): return [],'no_entry'
    e=i+1; noexit=e==len(p)-1; q=p[e] if noexit else p[-1]
    sides=(('BACK_SHORT',back_pl),('LAY_SHORT',lay_pl)) if kind=='S' else (('LAY_DRIFT',lay_pl),('BACK_DRIFT',back_pl))
    out=[]
    for s,f in sides:
        pl=f(p[e],q)
        if pl is None: continue
        out.append(dict(m=mid,mt=mt,kind=kind,side=s,p=p[e],q=q,mins=mt-ts[e],hold=ts[-1]-ts[e],age=mt-ts[-1],r=p[i]/p[i-1],np_=len(p),pl=np.nan if noexit else pl,g=np.nan if noexit else f(p[e],q,0),scr=pl,noexit=noexit))
    return out,'no_exit' if noexit else 'traded'
_t,_f=sim_runner('x',600.0,np.array([0.0,60,120,180]),[5.0,4.5,4.6,4.0])
assert _f=='traded' and _t[0]['side']=='BACK_SHORT' and _t[0]['p']==4.6 and _t[0]['q']==4.0 and abs(_t[0]['pl']-net(10*(4.5/4.1-1)))<1e-9 and _t[0]['mins']==480 and _t[0]['hold']==60
_t,_f=sim_runner('x',0,np.array([0,1,2]),[5.0,4.5,4.6]); assert _f=='no_exit' and np.isnan(_t[0]['pl']) and abs(_t[0]['scr']-back_pl(4.6,4.6))<1e-9
print("simulator checks: OK",flush=True)
def connect():
    c=psycopg2.connect(DB,sslmode='require'); c.autocommit=True; k=c.cursor(); k.execute("SET work_mem='64MB'"); k.execute("SET statement_timeout='2400s'"); return c
con=connect(); cur=con.cursor()
cur.execute("""WITH RECURSIVE t AS (
  (SELECT market_id FROM bf_hist_other WHERE sport='Greyhound Racing' ORDER BY market_id LIMIT 1)
  UNION ALL SELECT (SELECT market_id FROM bf_hist_other WHERE sport='Greyhound Racing' AND market_id>t.market_id ORDER BY market_id LIMIT 1) FROM t WHERE t.market_id IS NOT NULL)
  SELECT market_id FROM t WHERE market_id IS NOT NULL""")
ids=[r[0] for r in cur.fetchall()]; random.Random(58).shuffle(ids); print(f"greyhound markets {len(ids)} ({time.time()-T0:.0f}s)",flush=True)
SQL="SELECT market_id,market_time,sel,ts,ltp::float ltp FROM bf_hist_other WHERE sport='Greyhound Racing' AND market_type='WIN' AND NOT inplay AND ltp>=1.01 AND ltp<1000 AND market_id=ANY(%s)"
tr=[]; flags={'none':0,'no_entry':0,'no_exit':0,'traded':0}; done=0; rows=0; dup=0; late=[]
for i in range(0,len(ids),500):
    if time.time()-T0>BUDGET: print(f"TIME BUDGET hit: {done} of {len(ids)} markets",flush=True); break
    chunk=ids[i:i+500]
    try: P=pd.read_sql(SQL,con,params=(chunk,))
    except Exception as e:
        print("chunk retry:",type(e).__name__,flush=True); con=connect(); P=pd.read_sql(SQL,con,params=(chunk,))
    done+=len(chunk); rows+=len(P)
    if not len(P): continue
    P['t']=to_min(P.ts); P['mt']=to_min(P.market_time)
    n0=len(P); P=P.sort_values(['market_id','sel','t']).drop_duplicates(['market_id','sel','t'],keep='last'); dup+=n0-len(P)
    for (mid,sl),x in P.groupby(['market_id','sel'],sort=False):
        ts=x.t.values; p=x.ltp.values.tolist(); mt=float(x.mt.iloc[0])
        late.append(ts[-1]-mt)
        o,f=sim_runner(mid,mt,ts,p); flags[f]+=1; tr.extend(o)
    if (i//500)%20==0: print(f"  {done}/{len(ids)} rows {rows} trades {len(tr)} {time.time()-T0:.0f}s",flush=True)
con.close()
R=pd.DataFrame(tr); R['date']=pd.to_datetime(R.mt,unit='m',utc=True); assert R.date.min().year>=2024; MED=R.date.median()
R['half']=np.where(R.date<=MED,1,2)
print(f"\nmarkets read {done} of {len(ids)}; rows {rows}; duplicate-ts prints removed {dup}; dates {R.date.min():%Y-%m-%d} to {R.date.max():%Y-%m-%d}; median date {MED:%Y-%m-%d}")
print("runner outcomes",flags)
print("last pre-off print minus market time, minutes:",pd.Series(late).describe(percentiles=[.05,.5,.95]).round(2).to_dict())
s=R[R.kind!='C']; print(f"entries with no later print to exit at: {s.noexit.mean():.3f} of signal entries")
print("median minutes to off at entry",round(float(s.mins.median()),1),"; median hold",round(float(s[~s.noexit].hold.median()),1),"; moved entry to exit, median ratio",round(float((s[~s.noexit].q/s[~s.noexit].p).median()),4))
R.to_pickle('/tmp/499_greyhound_momentum.pkl')
R['pb']=pd.cut(R.p,[1,3,5,8,13,1001],labels=['p<=3','3-5','5-8','8-13','13+'])
R['mb']=pd.cut(R.mins,[-1e9,2,5,15,60,1e9],labels=['<2m','2-5m','5-15m','15-60m','60m+'])
def line(x,name):
    v=x.dropna(subset=['pl'])
    if len(v)<2: return None
    cl=v.groupby('m').pl.sum()
    a=v[v.half==1].pl; b=v[v.half==2].pl
    return dict(line=name,n=len(v),races=v.m.nunique(),per10=v.pl.mean(),t=tstat(v.pl),t_race=tstat(cl)*1.0,h1=a.mean() if len(a) else np.nan,n1=len(a),h2=b.mean() if len(b) else np.nan,n2=len(b),gross=v.g.mean(),scr=x.scr.mean())
L=[]
for scope in ('ALL','FIRST'):
    D=R[R.kind!='C']
    if scope=='FIRST': D=D.sort_values(['m','side','mins'],ascending=[True,True,False]).drop_duplicates(['m','side'],keep='first')
    for sd,x in D.groupby('side'):
        L.append(line(x,f"{scope} {sd} all"))
        for pb,y in x.groupby('pb',observed=True):
            L.append(line(y,f"{scope} {sd} {pb} all"))
            for mb,z in y.groupby('mb',observed=True): L.append(line(z,f"{scope} {sd} {pb} {mb}"))
        for mb,y in x.groupby('mb',observed=True): L.append(line(y,f"{scope} {sd} all {mb}"))
T=pd.DataFrame([l for l in L if l]);
T['PASS']=(T.n>=300)&(T.n1>=150)&(T.n2>=150)&(T.h1>0)&(T.h2>0)&(T.t>=3.5)&(T.per10>=0.15)
print(f"\nlines {len(T)}; with n>=300 {int((T.n>=300).sum())}")
C=R[R.kind=='C']
print("\n== CONTROL: no signal, second print to last")
print(pd.DataFrame([line(x,sd) for sd,x in C.groupby('side')]).round(3).to_string(index=False))
print("\n== THE FOUR SIDES, all prices and times")
print(T[T.line.str.endswith(' all')&T.line.str.count(' ').eq(2)].round(3).to_string(index=False))
print("\n== TOP 15 by t, n>=300")
print(T[T.n>=300].sort_values('t',ascending=False).head(15).round(3).to_string(index=False))
print("\n== BOTTOM 5 by t, n>=300")
print(T[T.n>=300].sort_values('t').head(5).round(3).to_string(index=False))
S=T[T.PASS]; print(f"\n== SURVIVORS: {len(S)} of {len(T)} lines")
if len(S):
    print(S.sort_values('t',ascending=False).round(3).to_string(index=False))
    print("\nSURVIVOR checks: race-clustered t, mean with no-exit scratches (scr), by quarter of dates")
    for nm in S.sort_values('t',ascending=False).line.head(5):
        pt=(nm.split(' ')+['all'])[:4]; x=R[(R.kind!='C')&(R.side==pt[1])]
        if pt[0]=='FIRST': x=x.sort_values(['m','side','mins'],ascending=[True,True,False]).drop_duplicates(['m','side'],keep='first')
        if pt[2]!='all': x=x[x.pb==pt[2]]
        if pt[3]!='all': x=x[x.mb==pt[3]]
        v=x.dropna(subset=['pl']).sort_values('date'); q=pd.qcut(np.arange(len(v)),4,labels=False)
        print(nm,"| quarters"," ".join(f"{v[q==k].pl.mean():+.2f}" for k in range(4)))
        f=lay_pl if 'LAY' in pt[1] else back_pl
        print("   cost, ticks each way:"," ".join(f"k{k} {np.nanmean([np.nan if (w:=f(a,b,k)) is None else w for a,b in zip(v.p,v.q)]):+.3f}" for k in (0,1,2,3,5,8)))
        print("   by exit age, min before off:"," ".join(f"{lo}-{hi} n {len(g)} {g.pl.mean():+.3f}" for lo,hi in ((-1e9,0),(0,1),(1,5),(5,60),(60,1e9)) for g in [v[(v.age>lo)&(v.age<=hi)]] if len(g)))
        print("   by hold, min:"," ".join(f"{lo}-{hi} n {len(g)} {g.pl.mean():+.3f} t {tstat(g.pl):.1f}" for lo,hi in ((-1,0),(0,1),(1,5),(5,30),(30,120),(120,1e9)) for g in [v[(v.hold>lo)&(v.hold<=hi)]] if len(g)>1))
        print("   by signal move:"," ".join(f"{lo}-{hi} n {len(g)} {g.pl.mean():+.3f}" for lo,hi in ((1.1,1.2),(1.2,1.5),(1.5,2),(2,1e9)) for g in [v[(v.r>=lo)&(v.r<hi)]] if len(g)))
        print("   by month, last 8:"," ".join(f"{k} {g.pl.mean():+.2f}" for k,g in list(v.groupby(v.date.dt.strftime('%y-%m')))[-8:]))
        c=R[(R.side=='CTRL_LAY' if 'LAY' in pt[1] else R.side=='CTRL_BACK')]
        if pt[2]!='all': c=c[c.pb==pt[2]]
        if pt[3]!='all': c=c[c.mb==pt[3]]
        print(f"   control, same price and time band: n {c.pl.count()} {c.pl.mean():+.3f} t {tstat(c.pl.dropna()):.1f}")
print(f"total {time.time()-T0:.0f}s")
PY
