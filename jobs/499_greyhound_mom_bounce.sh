#!/bin/bash
set -o pipefail
# 499_greyhound_mom_bounce (Finder 2026-11-04, queue item 58 follow-up): are the numeric passes of jobs/499_greyhound_momentum.sh order information, or back/lay bounce on thin prints? Diagnostics on those lines only; nothing here selects a new line and the gate is not re-applied. The number 499 is reused: 450-499 are all taken.
# Same rule, same costs. SAMPLE: the first 40,000 markets of that job's shuffle (seed 58), to stay in time.
# (a) FELL/HELD: entry print fell back through the signal print, or held. (b) DELAY: enter one print later. (c) EXIT-1: exit at the print before the last, if it is after the entry.
# (d) SHUFFLE PLACEBO: each runner's prices in random order on the same timestamps, same rule. Order carries no information there, so anything left is selection or arithmetic. A real momentum edge should be well above its placebo.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,time,random,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
pd.set_option('display.width',240); pd.set_option('display.max_rows',100); pd.set_option('display.max_columns',30)
T0=time.time(); BUDGET=1500; NM=40000
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
    return np.nan if a<=1.01 else net(10*(a/step(q,k)-1))
def lay_pl(p,q,k=1):
    a=step(p,k)
    return np.nan if a<=1.01 else net(10/(a-1)*(1-a/step(q,-k)))
def first_signal(p,th=0.10):
    for i in range(1,len(p)):
        r=round(p[i]/p[i-1],6)
        if r<=round(1-th,6): return i,'S'
        if r>=round(1+th,6): return i,'D'
    return None,None
def tstat(x):
    x=np.asarray(x,dtype=float); x=x[~np.isnan(x)]; s=x.std(ddof=1) if len(x)>1 else 0
    return x.mean()/(s/len(x)**0.5) if s>0 else 0.0
EPOCH=pd.Timestamp('1970-01-01',tz='UTC')
def to_min(c): return (pd.to_datetime(c,utc=True)-EPOCH)/pd.Timedelta(minutes=1)
def sim(mid,mt,ts,p):
    i,kind=first_signal(p)
    if i is None or i+1>=len(p)-1: return []
    e=i+1; n=len(p); out=[]
    for side,f in ((('BACK_SHORT',back_pl),) if kind=='S' else (('LAY_DRIFT',lay_pl),('BACK_DRIFT',back_pl))):
        out.append(dict(m=mid,side=side,p=p[e],sig=p[i],mins=mt-ts[e],pl=f(p[e],p[-1]),
            delay=f(p[e+1],p[-1]) if e+1<n-1 else np.nan,
            exit1=f(p[e],p[-2]) if n-2>e else np.nan,
            held=(p[e]>=p[i]) if kind=='D' else (p[e]<=p[i])))
    return out
# known answers, worked by hand
_o=sim('x',100.0,np.array([0.0,10,20,30,40]),[5.0,5.5,5.4,6.0,6.5])
_l=[r for r in _o if r['side']=='LAY_DRIFT'][0]
assert _l['p']==5.4 and _l['sig']==5.5 and not _l['held']
assert abs(_l['pl']-lay_pl(5.4,6.5))<1e-9 and abs(_l['delay']-lay_pl(6.0,6.5))<1e-9 and abs(_l['exit1']-lay_pl(5.4,6.0))<1e-9 and _l['mins']==80
assert lay_pl(5.4,6.5)>0 and back_pl(5.4,6.5)<0     # a price that rises pays the lay and costs the back
assert sim('x',0.0,np.array([0.0,1,2]),[5.0,5.5,5.4])==[]   # the entry print is the last: no exit, not scored here
assert first_signal([5.0,4.5])==(1,'S')
print("checks: OK",flush=True)
LINES=[('FIRST','LAY_DRIFT',1,3,-1e9,1e9),('ALL','LAY_DRIFT',1,3,5,15),('FIRST','LAY_DRIFT',1,3,5,15),('ALL','LAY_DRIFT',1,3,15,60),('FIRST','LAY_DRIFT',1,3,15,60),('FIRST','BACK_SHORT',5,8,15,60),('ALL','BACK_SHORT',5,8,15,60),('FIRST','BACK_SHORT',3,5,15,60),('ALL','BACK_SHORT',3,5,15,60),('FIRST','BACK_SHORT',1,1001,15,60),('ALL','BACK_SHORT',1,1001,15,60),('ALL','BACK_DRIFT',13,1001,15,60)]
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'"); cur.execute("SET statement_timeout='2400s'")
cur.execute("""WITH RECURSIVE t AS (
  (SELECT market_id FROM bf_hist_other WHERE sport='Greyhound Racing' ORDER BY market_id LIMIT 1)
  UNION ALL SELECT (SELECT market_id FROM bf_hist_other WHERE sport='Greyhound Racing' AND market_id>t.market_id ORDER BY market_id LIMIT 1) FROM t WHERE t.market_id IS NOT NULL)
  SELECT market_id FROM t WHERE market_id IS NOT NULL""")
ids=[r[0] for r in cur.fetchall()]; random.Random(58).shuffle(ids); ids=ids[:NM]; print(f"markets {len(ids)} ({time.time()-T0:.0f}s)",flush=True)
SQL="SELECT market_id,market_time,sel,ts,ltp::float ltp FROM bf_hist_other WHERE sport='Greyhound Racing' AND market_type='WIN' AND NOT inplay AND ltp>=1.01 AND ltp<1000 AND market_id=ANY(%s)"
rng=np.random.default_rng(58); A=[]; B=[]; done=0
for i in range(0,len(ids),500):
    if time.time()-T0>BUDGET: print(f"TIME BUDGET hit at {done}",flush=True); break
    P=pd.read_sql(SQL,con,params=(ids[i:i+500],)); done+=500
    if not len(P): continue
    P['t']=to_min(P.ts); P['mt']=to_min(P.market_time); P=P.sort_values(['market_id','sel','t']).drop_duplicates(['market_id','sel','t'],keep='last')
    for (mid,sl),x in P.groupby(['market_id','sel'],sort=False):
        ts=x.t.values; p=x.ltp.values.tolist(); mt=float(x.mt.iloc[0])
        A.extend(sim(mid,mt,ts,p)); B.extend(sim(mid,mt,ts,rng.permutation(p).tolist()))
    if (i//500)%20==0: print(f"  {done}/{len(ids)} {time.time()-T0:.0f}s",flush=True)
con.close()
A=pd.DataFrame(A); B=pd.DataFrame(B); print(f"read {done} markets; entries {len(A)}; placebo entries {len(B)}")
def pick(D,sc,sd,lo,hi,a,b):
    x=D[D.side==sd]
    if sc=='FIRST': x=x.sort_values(['m','mins'],ascending=[True,False]).drop_duplicates('m',keep='first')
    return x[(x.p>lo)&(x.p<=hi)&(x.mins>a)&(x.mins<=b)]
o=[]
for sc,sd,lo,hi,a,b in LINES:
    x=pick(A,sc,sd,lo,hi,a,b); y=pick(B,sc,sd,lo,hi,a,b); h=x[x.held==True]; f=x[x.held==False]
    o.append(dict(line=f"{sc} {sd} {lo}-{hi} {'all' if a<0 else f'{a}-{b}m'}",n=len(x),per10=x.pl.mean(),t=tstat(x.pl),held_n=len(h),held=h.pl.mean(),fell_n=len(f),fell=f.pl.mean(),delay=x.delay.mean(),t_delay=tstat(x.delay),exit1=x.exit1.mean(),placebo_n=len(y),placebo=y.pl.mean(),t_placebo=tstat(y.pl)))
print("\n== DIAGNOSTICS on the lines that passed, 40,000-market sample"); print(pd.DataFrame(o).round(3).to_string(index=False))
print("\n== SURVIVORS: diagnostics only, gate not re-applied"); print(f"total {time.time()-T0:.0f}s")
PY
