#!/bin/bash
set -o pipefail
# 499_book_thin (Finder 2026-11-06, queue item 206, Finder's own, source a): does a goal-line book that thins at a steady price warn of a goal? Rule pushed before any price was read. The number 499 is reused: 450-499 are all taken.
# DATA liq_sample, real touch, snapshots about 64 s apart, about 6 days: a pilot. Costs and exits from lib_wom.trade_h: one tick adverse each way, 2%, £10 risk; market gone = settled from the last print, unresolved counted. A goal line that passes closes its market, so it settles at the result and is never dropped.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))  # this job only
import sys,time,warnings,psycopg2,pandas as pd,numpy as np
from collections import Counter
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_wom import ticks,trade_h,table
T0=time.time(); GAP=180
def windows(m): return ((m>=5)&(m<=40))|((m>=50)&(m<=85))
def signals(t,bp,lp,d,m):
    """Index of the first signal per state: {state:i}. Baseline from the 10 rows before i, spread and depth medians on rows with a book only; the signal row itself is never in its own baseline."""
    n=len(t); out={}
    with np.errstate(invalid='ignore',divide='ignore'):
        book=(bp>=1.05)&(lp<=10)&(lp>bp); mid=(bp+lp)/2
    for i in range(10,n):
        if not book[i] or not book[i-1] or not windows(m[i:i+1])[0]: continue
        if t[i]-t[i-1]>GAP or abs(mid[i]/mid[i-1]-1)>0.05: continue
        idx=np.arange(i-10,i); use=idx[book[idx]]
        if len(use)<8 or t[i-1]-t[i-10]>1200: continue
        md=np.median(d[use]); ms=np.median(ticks(bp[use],lp[use]))
        if not md>=100: continue
        s=int(ticks(bp[i],lp[i])); r=d[i]/md
        if r<=0.4: out.setdefault('THIN',i)
        if s>=3 and s>=2*ms: out.setdefault('WIDE',i)
        if 0.8<=r<=1.25 and s<=ms: out.setdefault('CTRL',i)
    return out
# known answers, worked by hand
assert windows(np.array([4,5,40,41,49,50,85,86])).tolist()==[False,True,True,False,False,True,True,False]
_t=np.arange(14)*60.; _b=np.full(14,2.0); _l=np.full(14,2.02); _d=np.full(14,500.); _m=np.full(14,20.)
assert signals(_t,_b,_l,_d,_m)=={'CTRL':10}                      # flat book: first eligible row is a control
_d2=_d.copy(); _d2[12]=200.; assert signals(_t,_b,_l,_d2,_m)=={'CTRL':10,'THIN':12}   # 200/500 = 0.4 is thin, inclusive
_d3=_d.copy(); _d3[12]=201.; assert 'THIN' not in signals(_t,_b,_l,_d3,_m)
_l2=_l.copy(); _l2[11]=2.06; assert signals(_t,_b,_l2,_d,_m)['WIDE']==11    # 3 ticks v median 1
_l3=_l.copy(); _l3[11]=2.04; assert 'WIDE' not in signals(_t,_b,_l3,_d,_m)    # 2 ticks: under the 3-tick floor
_b4=_b.copy(); _l4=_l.copy(); _b4[11:]=2.2; _l4[11:]=2.22; _d4=_d.copy(); _d4[11]=100.
assert 'THIN' not in signals(_t,_b4,_l4,_d4,_m)                  # a 10% jump the same row is not a steady price
assert signals(_t,_b,_l,np.full(14,50.),_m)=={}                  # baseline depth under 100: no signal
assert signals(_t,_b,_l,_d,np.full(14,45.))=={}                  # half-time: no signal
print("checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
D=pd.read_sql("""SELECT extract(epoch from ts)::float8 t,market_id,event_name ev,mkt,sel,minute::float8 m,ltp::float8 ltp,back_px::float8 bp,lay_px::float8 lp,back3_sz::float8 b3,lay3_sz::float8 l3
 FROM liq_sample WHERE mkt IN ('OU15','OU25','OU35') AND sel LIKE 'OVER%%'""",con); con.close()   # OU25 reads OVER, OU15 and OU35 read OVER 1.5 GOALS, OVER 3.5 GOALS
assert set(D.mkt)=={'OU15','OU25','OU35'} and D.groupby('market_id').sel.nunique().max()==1
_n=len(D); D=D.drop_duplicates(); _x=D[D.duplicated(['market_id','sel','t'],keep=False)].market_id.unique()
print(f"data: rows {_n:,}, exact duplicates dropped {_n-len(D)}, markets dropped for two rows at one time {len(_x)}",flush=True)
D=D[~D.market_id.isin(_x)].sort_values(['market_id','t'],kind='mergesort')
print(f"markets {D.market_id.nunique():,}, games {D.ev.nunique():,}, {pd.to_datetime(D.t.min(),unit='s')}..{pd.to_datetime(D.t.max(),unit='s')}, {time.time()-T0:.0f}s",flush=True)
S=Counter(); rows=[]; GOAL=[]
for (mk,mid_),x in D.groupby(['mkt','market_id'],sort=False):
    t,m,ltp,bp,lp=[x[c].values for c in 't m ltp bp lp'.split()]; d=x.b3.values+x.l3.values; ev=x.ev.iloc[0]; n=len(t)
    if n<12: S['short market']+=1; continue
    sg=signals(t,bp,lp,d,m)
    for st,i in sg.items():
        S[st+' signal']+=1; k=i+1
        if k>=n or t[k]-t[i]>GAP or not (bp[k]>=1.05 and lp[k]<=10 and lp[k]>bp[k]): S[st+' no entry']+=1; continue
        band='<2.5' if bp[i]<2.5 else '2.5-10'
        # context only, not a rule: did the Over shorten by 10% or the market close within 5 min of the signal? A proxy for a goal.
        j=np.searchsorted(t,t[i]+300,side='right')-1
        q=(bp[j]+lp[j])/2 if bp[j]==bp[j] and lp[j]==lp[j] else np.nan
        GOAL.append((mk,st,bool(j==n-1 or (q==q and q<=0.9*(bp[i]+lp[i])/2))))
        for side in ('back','lay'):
            for H in (5,10):
                p,e,how,w=trade_h(side,t,bp,lp,ltp,k,H); S[how]+=1; S['wide exit']+=w
                if p is not None: rows.append((mk,st,side,H,band,p,e,ev,t[k]))
print("counts",dict(sorted(S.items())),flush=True)
G=pd.DataFrame(GOAL,columns='mk st g'.split()); print("\nOver shortened 10% or market closed within 5 min of the signal, share, context only:"); print(G.groupby(['mk','st']).g.agg(['size','mean']).round(3).to_string())
R=pd.DataFrame(rows,columns='mk state side H band pnl exact ev ts'.split())
P=table(R,['mk','state','side','H','band'],'ITEM 206 book thinning at a steady price',control=('state','CTRL'))
print("\n== SURVIVORS (n >= 300, 150 per half, t >= 3.5, both halves > 0, mean >= +0.15; a game can appear on three lines, see tg)")
print('none' if P.empty else P.round(3).to_string(index=False))
print(f"total {time.time()-T0:.0f}s")
PY
