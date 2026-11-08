#!/bin/bash
set -o pipefail
# 499_mo_underround_ko (Finder 2026-11-08, queue item 461, Finder's own, source c structural, mirror of item 31's overround capture; built from jobs/499_mo_premarket_drift.sh; rule pushed in the claim commit before any price was read).
# Match Odds book at the off whose three last pre-off prints sum (1/ltp) under 100%: back the STALE leg (oldest last print) at its first print after the latest of the three, held to the official result.
# No lookahead: the decision time t* is the latest of the three last prints, so the entry is a print after t*, never the stale print itself.
# Entry: STALE's first print after t* within 10 min, pre-off, or in-play only if within 120 s of the market's first in-play print; worse of that print and the next within 120 s, one tick adverse, GBP 10 back, 2% on profit.
# Never dropped: every entry is held to the official MO result. One trade per game. Read only, no tables written. Prints only: a pass earns a real-touch read, not a stake.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line,step,back_settle,lay_settle
from lib_official import fill,first_in,secs,checks,group,load_results
import lib_cand; lib_cand._checks(); checks()
pd.set_option('display.width',230); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',300)
def sband(S):
    if S<0.97: return 'U3'
    if S<0.99: return 'U1'
    if S<=1.01: return 'FAIR'
    if S>1.03: return 'O3'
    return None
def bk(p,won):
    a=step(p,-1)
    return None if a<=1.01 else back_settle(a,won)
def ly(p,won): return lay_settle(step(p,1),won)
def stale_of(last):
    """last: {sel: (ts, ltp)} of the three last pre-off prints. Returns (S, t*, stale sel) or None if the oldest is not 60 s older than t*."""
    S=sum(1/p for _,p in last.values()); ts=max(t for t,_ in last.values())
    sel=min(last,key=lambda k:last[k][0])
    if ts-last[sel][0]<60: return None
    return S,ts,sel
# known answers, worked by hand
# 2.2, 3.6, 4.2: 0.45455+0.27778+0.23810=0.97042 -> U1; 2.3, 3.6, 4.4: 0.43478+0.27778+0.22727=0.93983 -> U3; 2.0, 3.5, 4.0: 0.5+0.28571+0.25=1.03571 -> O3
assert sband(1/2.2+1/3.6+1/4.2)=='U1' and sband(1/2.3+1/3.6+1/4.4)=='U3' and sband(1/2.0+1/3.5+1/4.0)=='O3' and sband(1.0)=='FAIR' and sband(1.02) is None
assert sband(0.97)=='U1' and sband(0.9699)=='U3' and sband(0.99)=='FAIR' and sband(1.01)=='FAIR' and sband(1.03) is None
r=stale_of({'A':(100.,2.3),'B':(500.,3.6),'X':(400.,4.4)}); assert r[1]==500. and r[2]=='A' and abs(r[0]-0.93983)<1e-4
assert stale_of({'A':(470.,2.3),'B':(500.,3.6),'X':(480.,4.4)}) is None
# back 4.4 -> 4.3 wins 33*0.98=32.34; loses 10; lay 4.4 -> 4.5 liability 10, stake 10/3.5, wins 2.857*0.98=2.8
assert abs(bk(4.4,True)-33*0.98)<1e-9 and bk(4.4,False)==-10.0 and abs(ly(4.4,False)-10/3.5*0.98)<1e-9 and ly(4.4,True)==-10.0
print("checks: OK",flush=True); T0=time.time()
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
RES,drop=load_results(con,['MATCH_ODDS'])
print("official MO markets",len(RES),"dropped (not one winner)",drop,f"{time.time()-T0:.0f}s",flush=True)
C=Counter(); rows=[]
def chunks():
    for y,ms in ((2022,range(11,13)),(2023,range(1,13)),(2024,range(1,13)),(2025,range(1,13)),(2026,range(1,11))):
        for m in ms:
            a=pd.Timestamp(y,m,1); e=a+pd.offsets.MonthBegin(1)
            while a<e:
                b=min(a+pd.Timedelta(days=10),e); yield str(a.date()),str(b.date()); a=b
for lo,hi in chunks():
    X=pd.read_sql("""SELECT market_id,event_id,event_name ev,market_time mt,sel,inplay,ts,ltp::float8 ltp FROM bf_hist_other
                     WHERE sport='Soccer' AND market_type='MATCH_ODDS' AND ltp>=1.01 AND ltp<1000
                     AND market_time>=%s AND market_time<%s AND ts>=market_time-interval '10 minutes' AND ts<=market_time+interval '25 minutes'""",con,params=(lo,hi))
    if X.empty: C['empty chunks']+=1; continue
    X['tt']=secs(X.ts); X['ko']=secs(X.mt)
    X=X.sort_values(['market_id','sel','tt'],kind='stable').drop_duplicates(['market_id','sel','tt'],keep='last')
    first_mk=X.groupby('event_id').market_id.min().to_dict(); nt=0
    for (e,mk),g in X.groupby(['event_id','market_id'],sort=False):
        if first_mk[e]!=mk: continue
        ev=g.ev.iloc[0]; ko=float(g.ko.iloc[0]); C['games']+=1
        if not isinstance(ev,str) or ' v ' not in ev: C['no H v A']+=1; continue
        if group(ev): C['women or youth']+=1; continue
        res=RES.get(mk)
        if res is None: C['no official']+=1; continue
        pre=g[~g.inplay]; ip=g[g.inplay]
        ip0=float(ip.tt.min()) if len(ip) else None
        last={}
        for sel,x in pre.groupby('sel',sort=False):
            x=x[x.tt<=ko+600]
            if len(x): last[sel]=(float(x.tt.values[-1]),float(x.ltp.values[-1]))
        if len(last)!=3 or set(last)-set(res): C['not three runners with a print']+=1; continue
        st=stale_of(last)
        if st is None: C['stale under 60 s older']+=1; continue
        S,ts_,sel=st; b=sband(S)
        if b is None: C['S 1.01-1.03']+=1; continue
        x=g[g.sel==sel]; tt=x.tt.values; px=x.ltp.values; inp=x.inplay.values
        i=first_in(tt,ts_+0.001,ts_+600)
        if i is None: C[b+' no STALE print after t*']+=1; continue
        if inp[i] and (ip0 is None or tt[i]-ip0>120): C[b+' next print in-play past 120 s']+=1; continue
        # worse of the print and the next within 120 s, within the same state only
        same=(inp==inp[i]); tts=tt[same]; pxs=px[same]; k=int(np.searchsorted(tts,tt[i]))
        pb=fill(tts,pxs,k,'B'); pl=fill(tts,pxs,k,'L')
        won=bool(res[sel]); vb=bk(pb,won); vl=ly(pl,won)
        if vb is None: C['back at ladder floor']+=1; continue
        stale_px=last[sel][1]
        rows.append(dict(e=e,ko=ko,band=b,S=S,sel=sel,draw=sel=='The Draw',stale_px=stale_px,pin=pb,inplay=bool(inp[i]),age=ts_-last[sel][0],won=won,vb=vb,vl=vl,imp=1/pb))
        C[b+' trades']+=1; nt+=1
    print(lo,"rows",len(X),"games",X.event_id.nunique(),"trades",nt,f"{time.time()-T0:.0f}s",flush=True); del X
con.close(); print("counts",dict(sorted(C.items())),flush=True)
T=pd.DataFrame(rows)
if T.empty: print("\n== SURVIVORS\nnone (no trades)"); sys.exit(0)
def row(nm,x,col='vb'):
    if len(x)<2: return dict(line=nm,n=len(x))
    x=x.sort_values('ko'); med=x.ko.median(); h=np.where(x.ko<=med,1,2)
    v=x[col].astype(float).values; d=line(v,h)
    return dict(line=nm,n=d['n'],games=x.e.nunique(),per10=round(d['per10'],3),t=round(d['t'],2),h1=round(d['h1'],3),h2=round(d['h2'],3),n1=d['n1'],n2=d['n2'],
                no_top=round(np.delete(v,v.argmax()).mean(),3),won=round(x.won.mean(),3),imp=round(x.imp.mean(),3),PASS=d['PASS'])
print(f"\ntrades {len(T)}, games {T.e.nunique()}, months {pd.to_datetime(T.ko,unit='s').dt.strftime('%Y-%m').nunique()}; halves by date median within each line")
print("by band: n, median S, median stale age s, share entered in-play, share STALE next print shorter than stale print, median next/stale-1")
T['shorter']=T.pin<T.stale_px; T['mv']=T.pin/T.stale_px-1
print(T.groupby('band').agg(n=('e','size'),S=('S','median'),age=('age','median'),inplay=('inplay','mean'),shorter=('shorter','mean'),mv=('mv','median')).round(4).to_string())
o=[row('U3 STALE back *',T[T.band=='U3']),row('U1 STALE back *',T[T.band=='U1'])]
O=pd.DataFrame(o); print("\n== ITEM 461, scored lines\n",O.to_string(index=False))
r=[row('U3 STALE lay (mirror)',T[T.band=='U3'],'vl'),row('U1 STALE lay (mirror)',T[T.band=='U1'],'vl'),
   row('FAIR STALE back (control)',T[T.band=='FAIR']),row('FAIR STALE lay (control)',T[T.band=='FAIR'],'vl'),
   row('O3 STALE lay',T[T.band=='O3'],'vl'),row('O3 STALE back',T[T.band=='O3']),
   row('U3 STALE back, pre-off entries only',T[(T.band=='U3')&~T.inplay]),row('U3 STALE back, Draw',T[(T.band=='U3')&T.draw]),row('U3 STALE back, not Draw',T[(T.band=='U3')&~T.draw]),
   row('U3 STALE back, entry < 3.0',T[(T.band=='U3')&(T.pin<3)]),row('U3 STALE back, entry >= 3.0',T[(T.band=='U3')&(T.pin>=3)])]
for y in sorted(pd.to_datetime(T.ko,unit='s').dt.year.unique()):
    r.append(row(f'U3+U1 STALE back year {y}',T[(T.band.isin(['U3','U1']))&(pd.to_datetime(T.ko,unit='s').dt.year==y)]))
R_=pd.DataFrame(r); print("\n-- for reading, not scored\n",R_.to_string(index=False))
P_=O[O.PASS==True]
print("\n== SURVIVORS"); print(P_.to_string(index=False) if len(P_) else "none",flush=True); print(f"total {time.time()-T0:.0f}s")
PY
