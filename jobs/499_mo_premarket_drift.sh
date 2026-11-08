#!/bin/bash
set -o pipefail
# 499_mo_premarket_drift (Finder 2026-11-08, queue item 456, Finder's own, source c/d; built from jobs/499_ou05_late_full.sh; rule pushed in the claim commit before any MO price was read).
# Match Odds pre-match swing: enter at the last print of a runner in [KO-W-1h, KO-W], W = 24, 6, 2 hours; trade out at the last pre-off print of the same runner in [KO-30 min, KO+10 min].
# No exit print: the runner's first in-play print within 10 min of the market's first in-play print; none: the official MO result. Never dropped.
# Worse of the print and the next within 120 s, one tick adverse at entry and exit, GBP 10 stake (back) or liability (lay), 2% on a green profit, entry 1.01-20.
# One runner per game per line (the shortest in the band). Read only, no tables written. Prints only: a pass is an upper bound and earns a real-touch read, not a stake.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line,step,back_hedge,lay_hedge,back_settle,lay_settle
from lib_official import fill,last_in,first_in,secs,checks,group,load_results
import lib_cand; lib_cand._checks(); checks()
pd.set_option('display.width',230); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',300)
WS=(24,6,2)
BANDS=((1.01,1.6),(1.6,2.5),(2.5,4.0),(4.0,8.0),(8.0,20.0))
def band(p):
    for lo,hi in BANDS:
        if lo<=p<hi: return f'{lo:g}-{hi:g}'
    return None
def role(sel,ev):
    if sel=='The Draw': return 'DRAW'
    h,_,a=ev.partition(' v ')
    return 'HOME' if sel==h.strip() else ('AWAY' if sel==a.strip() else 'OTHER')
def pnl(side,p_in,p_out,won):
    """side B: back at p_in one tick adverse, out by laying p_out one tick adverse (p_out None: settle on won). Mirror for L. None if the back fill is at the ladder floor."""
    if side=='B':
        a=step(p_in,-1)
        if a<=1.01: return None
        return back_hedge(a,p_out) if p_out is not None else back_settle(a,won)
    a=step(p_in,1)
    return lay_hedge(a,p_out) if p_out is not None else lay_settle(a,won)
# known answers, worked by hand
assert band(1.01)=='1.01-1.6' and band(1.6)=='1.6-2.5' and band(19.5)=='8-20' and band(20)is None and band(1.0) is None
assert role('The Draw','A v B')=='DRAW' and role('Leeds','Leeds v Hull')=='HOME' and role('Hull','Leeds v Hull')=='AWAY'
# back 2.04 -> 2.02, out laying 1.90 -> 1.91: 10*(2.02/1.91-1)=0.57592, after 2% 0.56440
assert abs(pnl('B',2.04,1.90,None)-10*(2.02/1.91-1)*0.98)<1e-9 and abs(pnl('B',2.04,1.90,None)-0.5644)<1e-4
# back 2.04 -> 2.02, out laying 2.20 -> 2.22: 10*(2.02/2.22-1)=-0.9009, no commission on a loss
assert abs(pnl('B',2.04,2.20,None)-10*(2.02/2.22-1))<1e-9
# lay 2.0 -> 2.02 liability 10, stake 9.8039, out backing 2.2 -> 2.18: 9.8039*(1-2.02/2.18)=0.71955, after 2% 0.70516
assert abs(pnl('L',2.0,2.2,None)-0.70516)<1e-4
# settled at the result when no exit: back 3.0 -> 2.98 wins 19.8*0.98; lay 3.0 -> 3.05 loses 10
assert abs(pnl('B',3.0,None,True)-19.8*0.98)<1e-9 and pnl('L',3.0,None,True)==-10.0 and pnl('B',1.02,1.5,None) is None
print("checks: OK",flush=True); T0=time.time()
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
RES,drop=load_results(con,['MATCH_ODDS'])
print("official MO markets",len(RES),"dropped (not one winner)",drop,f"{time.time()-T0:.0f}s",flush=True)
C=Counter(); rows=[]
def months():
    for y,ms in ((2022,range(8,13)),(2023,range(1,13)),(2024,range(1,13)),(2025,range(1,13)),(2026,range(1,11))):
        for m in ms:
            a=pd.Timestamp(y,m,1); b=a+pd.offsets.MonthBegin(1)
            for s,e in ((a,a+pd.Timedelta(days=10)),(a+pd.Timedelta(days=10),a+pd.Timedelta(days=20)),(a+pd.Timedelta(days=20),b)): yield str(s.date()),str(e.date())
for lo,hi in months():
    P=pd.read_sql("""SELECT market_id,event_id,event_name ev,market_time mt,sel,ts,ltp::float8 ltp FROM bf_hist_other
                     WHERE sport='Soccer' AND market_type='MATCH_ODDS' AND NOT inplay AND ltp>=1.01 AND ltp<1000
                     AND market_time>=%s AND market_time<%s AND ts>=market_time-interval '25 hours' AND ts<=market_time+interval '10 minutes'""",con,params=(lo,hi))
    if P.empty: C['empty chunks']+=1; continue
    I=pd.read_sql("""SELECT DISTINCT ON (market_id,sel) market_id,sel,ts,ltp::float8 ltp FROM bf_hist_other
                     WHERE sport='Soccer' AND market_type='MATCH_ODDS' AND inplay AND ltp>=1.01 AND ltp<1000
                     AND market_time>=%s AND market_time<%s AND ts>=market_time-interval '30 minutes' AND ts<=market_time+interval '60 minutes'
                     ORDER BY market_id,sel,ts""",con,params=(lo,hi))
    I['tt']=secs(I.ts); IP0=I.groupby('market_id').tt.min().to_dict(); IPS={(m,s):(t,p) for m,s,t,p in zip(I.market_id,I.sel,I.tt,I.ltp)}
    P['tt']=secs(P.ts); P['ko']=secs(P.mt)
    P=P.sort_values(['market_id','sel','tt'],kind='stable').drop_duplicates(['market_id','sel','tt'],keep='last')
    first_mk=P.groupby('event_id').market_id.min().to_dict()
    nt=0
    for (e,mk),g in P.groupby(['event_id','market_id'],sort=False):
        if first_mk[e]!=mk: continue
        ev=g.ev.iloc[0]; ko=float(g.ko.iloc[0]); C['games']+=1
        if not isinstance(ev,str) or ' v ' not in ev: C['no H v A']+=1; continue
        if group(ev): C['women or youth']+=1; continue
        res=RES.get(mk)
        for W in WS:
            cand={}
            for sel,x in g.groupby('sel',sort=False):
                tt=x.tt.values; px=x.ltp.values
                i=last_in(tt,ko-(W+1)*3600,ko-W*3600)
                if i is None: continue
                cand[sel]=(tt,px,i)
            if not cand: C[f'W{W} no entry print']+=1; continue
            for side in ('B','L'):
                best={}
                for sel,(tt,px,i) in cand.items():
                    pin=fill(tt,px,i,side); b=band(pin)
                    if b is None: continue
                    if b not in best or pin<best[b][1]: best[b]=(sel,pin,tt,px)
                for b,(sel,pin,tt,px) in best.items():
                    j=last_in(tt,ko-1800,ko+600); how='pre'
                    if j is not None and j>last_in(tt,ko-(W+1)*3600,ko-W*3600):
                        pout=fill(tt,px,j,'L' if side=='B' else 'B')
                    else:
                        j=None; pout=None; ip=IPS.get((mk,sel)); ip0=IP0.get(mk)
                        if ip is not None and ip0 is not None and ip[0]-ip0<=600: pout=ip[1]; how='inplay'
                        elif res is not None and sel in res: how='result'
                        else: C['no exit, no result: unscored']+=1; continue
                    won=res.get(sel) if res else None
                    v=pnl(side,pin,pout,won)
                    if v is None: C['back at ladder floor']+=1; continue
                    C[f'exit {how}']+=1
                    rows.append(dict(e=e,ko=ko,W=W,side=side,band=b,sel=sel,role=role(sel,ev),pin=pin,pout=pout,how=how,v=v))
                    nt+=1
    print(lo,"rows",len(P),"games",P.event_id.nunique(),"trades",nt,f"{time.time()-T0:.0f}s",flush=True); del P,I,IPS
con.close(); print("counts",dict(sorted(C.items())),flush=True)
T=pd.DataFrame(rows)
if T.empty: print("\n== SURVIVORS\nnone (no trades)"); sys.exit(0)
med=T.drop_duplicates('e').ko.median(); T['h']=np.where(T.ko<=med,1,2)
print(f"\nhalves split at {pd.to_datetime(med,unit='s')}; trades {len(T)}, games {T.e.nunique()}")
T['mv']=np.where(T.pout.notna(),T.pout/T.pin-1,np.nan)
print("price move entry -> exit by W and band (median, mean of exit/entry-1; pre exits only)\n",
      T[(T.side=='B')&(T.how=='pre')].groupby(['W','band']).mv.agg(['size','median','mean']).round(4).to_string())
def row(nm,x):
    v=x.v.astype(float).values
    if len(v)<2: return dict(line=nm,n=len(v))
    d=line(v,x.h.values)
    return dict(line=nm,n=d['n'],games=x.e.nunique(),per10=round(d['per10'],3),t=round(d['t'],2),h1=round(d['h1'],3),h2=round(d['h2'],3),n1=d['n1'],n2=d['n2'],
                no_top=round(np.delete(v,v.argmax()).mean(),3),pre_exit=round((x.how=='pre').mean(),3),PASS=d['PASS'])
o=[]
for W in WS:
    for b in [f'{lo:g}-{hi:g}' for lo,hi in BANDS]:
        for side,sd in (('B','back'),('L','lay')): o.append(row(f'W{W} {b} {sd} *',T[(T.W==W)&(T.band==b)&(T.side==side)]))
O=pd.DataFrame(o)
print("\n== ITEM 456, thirty scored lines (sorted by t)\n",O.sort_values('t',ascending=False).to_string(index=False))
r=[]
for W in WS:
    for rl in ('HOME','AWAY','DRAW'):
        for side,sd in (('B','back'),('L','lay')): r.append(row(f'W{W} {rl} {sd} all bands',T[(T.W==W)&(T.role==rl)&(T.side==side)]))
    for side,sd in (('B','back'),('L','lay')): r.append(row(f'W{W} {sd} pre exits only (biased: drops the rest)',T[(T.W==W)&(T.side==side)&(T.how=='pre')]))
for y in sorted(pd.to_datetime(T.ko,unit='s').dt.year.unique()):
    for side,sd in (('B','back'),('L','lay')): r.append(row(f'all W {sd} year {y}',T[(pd.to_datetime(T.ko,unit='s').dt.year==y)&(T.side==side)]))
R_=pd.DataFrame(r); R_=R_[R_.n>=2]
print("\n-- for reading, not scored\n",R_.to_string(index=False))
P_=O[O.PASS==True]
print("\n== SURVIVORS"); print(P_.to_string(index=False) if len(P_) else "none",flush=True); print(f"total {time.time()-T0:.0f}s")
PY
