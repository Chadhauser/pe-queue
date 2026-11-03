#!/bin/bash
set -o pipefail
# 481 (Finder 2026-11-04, queue item 26): RACING IN-PLAY "SHORTENED 15% / 25%" on ip_tape (sport Horse Racing, WIN), real touch. PILOT: the tape is short, say n, re-queue weekly.
# SNAPSHOT: distinct ts of status OPEN rows with secs_since_start > 0, with a two-sided touch for that runner. OFF PRICE: the runner's back_px at the market's first in-play snapshot (the tape starts at the off, so this is just after it). Off price > 50 not traded.
# TRIGGER: first later snapshot where back_px <= off x (1-X), X = 15% or 25%. One entry per runner per market per X. Earlier triggers cannot see later prices.
# FILL: races move in seconds, so BACK fills at the WORSE of the trigger touch and the next snapshot's touch (none = the trigger touch), less one tick; LAY (mirror, "lay the leader") at the worse of the two lay_px, plus one tick.
# RESULT: winner = the one runner with back_px (or ltp) <= 1.05 on the market's last OPEN snapshot, others losers. No clean single winner = UNKNOWN. Reported KNOWN (diagnostic, never eligible) and WORST (unknown = -£10). Only WORST can pass.
# FIRST: one entry per race = the first runner to trigger, because runners in a race are correlated. Both ALL and FIRST are shown.
# COST: 2% commission, £10 risk (back stake / lay liability). Halves: date median of market_start. Splits: off-price band, field size, region from competition where present. The distance is only split if the event name carries it (checked below).
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,re,time,warnings,psycopg2,pandas as pd,numpy as np
from collections import defaultdict
from functools import lru_cache
warnings.filterwarnings('ignore')
pd.set_option('display.width',230); pd.set_option('display.max_rows',100); pd.set_option('display.max_columns',30)
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
def back_pnl(p,won):
    a=dn(p)
    if a<=1.01: return None
    return 10*(a-1)*0.98 if won else -10.0
def lay_pnl(p,won):
    a=up(p); return -10.0 if won else 10/(a-1)*0.98
def trigger(series,x):
    """series: list of (idx,back_px) in time order. Returns the position of the first later point at or below off*(1-x)."""
    off=series[0][1]
    for i,(_,b) in enumerate(series[1:],1):
        if b<=off*(1-x)+1e-9: return i
    return None
def winner(last):
    """last: dict runner -> price on the last OPEN snapshot."""
    w=[k for k,v in last.items() if v is not None and v<=1.05]
    return w[0] if len(w)==1 else None
def obv(p): return '<3' if p<3 else '3-6' if p<6 else '6-12' if p<12 else '12-50'
# known answers, worked by hand
assert abs(back_pnl(3.0,True)-10*1.98*0.98)<1e-9 and back_pnl(3.0,False)==-10.0 and back_pnl(1.02,True) is None        # 3.0 fills 2.98
assert abs(lay_pnl(3.0,False)-10/2.05*0.98)<1e-9 and lay_pnl(3.0,True)==-10.0                                          # 3.0 fills 3.05
assert trigger([(0,10.0),(1,9.0),(2,8.5),(3,7.0)],0.15)==2 and trigger([(0,10.0),(1,9.0),(2,8.5),(3,7.0)],0.25)==3     # 8.5 is exactly 15% down: triggers
assert trigger([(0,10.0),(1,9.0)],0.25) is None and trigger([(0,10.0)],0.15) is None
assert winner({'a':1.03,'b':40.0})=='a' and winner({'a':1.03,'b':1.04}) is None and winner({'a':2.0,'b':3.0}) is None and winner({'a':None,'b':1.05})=='b'
assert obv(2.99)=='<3' and obv(3.0)=='3-6' and obv(12.0)=='12-50'
print("known-answer checks: OK",flush=True)

con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
t0=time.time(); SPORT=['Horse Racing','horse_racing','7','Horse racing']
frames=[]
day=pd.Timestamp('2026-10-20',tz='UTC'); end=pd.Timestamp.now(tz='UTC')+pd.Timedelta(days=1)
while day<end:
    d=pd.read_sql("""SELECT ts,market_id,event_name,competition,market_start,sel_id,sel_name,ltp::float ltp,back_px::float bp,lay_px::float lp,secs_since_start ss FROM ip_tape
       WHERE sport=ANY(%s) AND ts>=%s AND ts<%s AND market_type='WIN' AND status='OPEN' AND secs_since_start>0""",con,params=(SPORT,day,day+pd.Timedelta(days=1)))
    if len(d): frames.append(d)
    print(f"  {day.date()} rows {len(d)} | {int(time.time()-t0)}s",flush=True)
    day+=pd.Timedelta(days=1)
if not frames: print("ERROR: no racing rows pulled, so no verdict"); sys.exit(1)
A=pd.concat(frames,ignore_index=True)
print(f"rows {len(A)} | markets {A.market_id.nunique()} | {A.ts.min()} .. {A.ts.max()}",flush=True)
print("event name samples:",A.event_name.drop_duplicates().head(6).tolist())
print("competition top:",A.competition.astype(str).value_counts().head(8).to_dict())
snaps=A.groupby('market_id').ts.nunique(); print("snapshots per market:",snaps.describe(percentiles=[.1,.5,.9]).round(1).to_dict())
gap=A.drop_duplicates(['market_id','ts']).sort_values(['market_id','ts']).groupby('market_id').ts.diff().dt.total_seconds(); print("seconds between snapshots:",gap.describe(percentiles=[.1,.5,.9]).round(1).to_dict(),flush=True)
SK=defaultdict(int); rows=[]; known=0; mk=0
for mid,g in A.groupby('market_id',sort=False):
    mk+=1; g=g.sort_values('ts'); tss=sorted(g.ts.unique()); tidx={t:i for i,t in enumerate(tss)}
    if len(tss)<3: SK['under 3 snapshots']+=1; continue
    field=g[g.ts==tss[0]].sel_id.nunique()
    la=g[g.ts==tss[-1]]; last={r.sel_id:(r.bp if pd.notna(r.bp) and r.bp>1 else (r.ltp if pd.notna(r.ltp) else None)) for r in la.itertuples()}
    win=winner(last); known+=int(win is not None)
    tr=[]; two=g[(g.bp>1)&(g.lp>1)&(g.lp<1000)]
    for sid,s in two.groupby('sel_id',sort=False):
        if s.ts.iloc[0]!=tss[0]: continue
        off=float(s.bp.iloc[0])
        if off>50: SK['off over 50']+=1; continue
        ser=[(tidx[t],float(b)) for t,b in zip(s.ts,s.bp)]; lays=dict((tidx[t],float(l)) for t,l in zip(s.ts,s.lp))
        for x,lab in ((0.15,'15%'),(0.25,'25%')):
            i=trigger(ser,x)
            if i is None: continue
            k,b=ser[i]; nb=ser[i+1][1] if i+1<len(ser) else b
            bfill=min(b,nb); lfill=max(lays[k],lays.get(ser[i+1][0],lays[k]) if i+1<len(ser) else lays[k])
            if lfill>=1000: continue
            tr.append((lab,k,sid,off,bfill,lfill))
    day_=pd.Timestamp(g.market_start.iloc[0]).date() if pd.notna(g.market_start.iloc[0]) else g.ts.iloc[0].date()
    for lab in ('15%','25%'):
        tt=sorted([t for t in tr if t[0]==lab],key=lambda t:t[1])
        for j,t in enumerate(tt):
            _,k,sid,off,bf,lf=t; w=None if win is None else (sid==win)
            rows.append(dict(x=lab,market=mid,sid=sid,day=day_,off=obv(off),field='<=8' if field<=8 else '9-12' if field<=12 else '13+',first=j==0,known=win is not None,
                             B=(back_pnl(bf,w) if w is not None else -10.0),L=(lay_pnl(lf,w) if w is not None else -10.0)))
print("skips:",dict(SK)); print(f"markets {mk} | clean single winner {known} ({known/max(mk,1):.1%})",flush=True)
R=pd.DataFrame(rows)
if R.empty: print("\n== SURVIVORS: 0\nnone"); sys.exit()
days=sorted(R.day.unique()); md=days[len(days)//2]; print(f"entries {len(R)} | races {R.market.nunique()} | days {days[0]}..{days[-1]} | halves split at {md}",flush=True)
def tstat(v): return v.mean()/(v.std(ddof=1)/np.sqrt(len(v))) if len(v)>1 and v.std(ddof=1)>0 else 0.0
def line(d,col,**k):
    v=d[col].dropna(); a=d[d.day<md][col].dropna(); b=d[d.day>=md][col].dropna(); kn=d[d.known][col].dropna()
    return dict(**k,n=len(v),races=d.market.nunique(),worst=v.mean() if len(v) else np.nan,t=tstat(v),n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,known=kn.mean() if len(kn) else np.nan,n_known=len(kn),
                PASS=len(v)>=300 and len(a)>=150 and len(b)>=150 and tstat(v)>=3.5 and a.mean()>0 and b.mean()>0 and v.mean()>=0.15)
out=[]
for (x,col),nm in {('15%','B'):'BACK',('25%','B'):'BACK',('15%','L'):'LAY',('25%','L'):'LAY'}.items():
    d=R[R.x==x]
    out.append(line(d,col,x=x,side=nm,set='ALL',split='-'))
    out.append(line(d[d['first']],col,x=x,side=nm,set='FIRST',split='-'))
    for dim in ('off','field'):
        for v,dd in d.groupby(dim): out.append(line(dd,col,x=x,side=nm,set='ALL',split=f'{dim} {v}'))
S=pd.DataFrame(out); print("\n== RESULTS per £10 (worst = unknown result is -£10; known = diagnostic only)\n",S.round(3).to_string(index=False))
W=S[S.PASS==True]; print(f"\n== SURVIVORS: {len(W)} of {len(S)} lines"); print(W.round(3).to_string(index=False) if len(W) else "none")
PY
