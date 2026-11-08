#!/bin/bash
set -o pipefail
# 499_nogoal_move_wide (Finder 2026-11-08, queue item 464: item 463's code, t0/t1 prints from the last 180 s, scored only on windows 463 could not price).
# Built from 499_nogoal_move (queue item 463, Finder's own, source a, breadth door of item 325 on the full print tape; built from jobs/499_ht_break_drift.sh;
# rule pushed in the claim commit 6b753a3 before any MO price was read).
# At 0-0, a Match Odds side (HOME or AWAY) that shortens 2-10 implied points over five minutes with no goal: back it (follow) or lay it (fade).
# Windows E = 25, 40, 70, 85 min after the first in-play MO print; t1 = ip0+E, t0 = t1-5 min; p0, p1 = last prints in the 60 s before t0 and t1 (no forward fill).
# No-goal guard: an Over 0.5 print above 1.05 in [t0, t1], and no Over 0.5 print at 1.05 or under at or before the entry print.
# Entry = the runner's first print in (t1, t1+120 s], worse of it and the next within 120 s, one tick adverse, prices 1.01-50.
# HEDGE: out at the runner's last print in [entry+8, entry+12 min], one tick adverse, 2% on a green; no print there -> held to the official result (never dropped).
# HOLD: to the official MO result. GBP 10 stake or liability. One entry per game per window per runner. Read only, no tables written. Prints only.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line,step,back_hedge,lay_hedge,back_settle,lay_settle
from lib_official import fill,first_in,last_in,secs,checks,group,load_results
import lib_cand; lib_cand._checks(); checks()
pd.set_option('display.width',230); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',300)
WINS=(25,40,70,85)
def cls(D):
    if 0.02<=D<0.04: return 'SH2'
    if 0.04<=D<0.10: return 'SH4'
    if D<=-0.04: return 'DR'
    if abs(D)<0.01: return 'FLAT'
    return None
def bk_out(p_in,q_out):
    a=step(p_in,-1); return None if a<=1.01 else back_hedge(a,q_out)
def ly_out(p_in,q_out):
    if step(q_out,-1)<=1.01: return None
    return lay_hedge(step(p_in,1),q_out)
def bk_res(p,won):
    a=step(p,-1); return None if a<=1.01 else back_settle(a,won)
def ly_res(p,won): return lay_settle(step(p,1),won)
def guard_ok(ot,op,t0,t1,te):
    """Over 0.5 prints ot (sorted), op: a print above 1.05 in [t0,t1], and none at 1.05 or under at or before te."""
    m=(ot>=t0)&(ot<=t1)&(op>1.05)
    if not m.any(): return False
    return not ((ot<=te)&(op<=1.05)).any()
# known answers, worked by hand
assert cls(1/2.0-1/2.1)=='SH2' and cls(1/2.0-1/2.25)=='SH4' and cls(1/2.0-1/3.0) is None and cls(1/2.4-1/2.0)=='DR' and cls(0.005)=='FLAT' and cls(0.015) is None
# 1/2.0-1/2.1 = 0.5-0.47619 = 0.0238 SH2; 1/2.0-1/2.25 = 0.0556 SH4; 1/2-1/3 = 0.1667 a goal, out
assert abs(bk_out(3.0,2.5)-10*(2.98/2.52-1)*0.98)<1e-9 and abs(ly_out(2.0,2.5)-(10/1.02)*(1-2.02/2.48)*0.98)<1e-9
assert abs(bk_res(4.4,True)-33*0.98)<1e-9 and bk_res(4.4,False)==-10.0 and abs(ly_res(4.4,False)-10/3.5*0.98)<1e-9 and ly_res(4.4,True)==-10.0
ot=np.array([100.,200.,400.]); op=np.array([1.4,1.35,1.02])
assert guard_ok(ot,op,150,250,300) and not guard_ok(ot,op,150,250,400) and not guard_ok(ot,op,250,350,300)
print("checks: OK",flush=True); T0=time.time()
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
RES,drop=load_results(con,['MATCH_ODDS'])
print("official MO markets",len(RES),"dropped (not one winner)",drop,f"{time.time()-T0:.0f}s",flush=True)
C=Counter(); rows=[]
def chunks():
    a=pd.Timestamp(2022,11,1)
    while a<pd.Timestamp(2026,11,1):
        b=a+pd.offsets.MonthBegin(1)
        for c0,c1 in ((a,a+pd.Timedelta(days=10)),(a+pd.Timedelta(days=10),a+pd.Timedelta(days=20)),(a+pd.Timedelta(days=20),b)):
            yield str(c0.date()),str(c1.date())
        a=b
for lo,hi in chunks():
    X=pd.read_sql("""SELECT market_id,event_id,event_name ev,market_type mt,sel,ts,ltp::float8 ltp FROM bf_hist_other
                     WHERE sport='Soccer' AND market_type IN ('MATCH_ODDS','OVER_UNDER_05') AND inplay AND ltp>=1.01 AND ltp<1000
                     AND market_time>=%s AND market_time<%s AND ts>=market_time-interval '30 minutes' AND ts<=market_time+interval '150 minutes'""",con,params=(lo,hi))
    if X.empty: C['empty chunks']+=1; continue
    X['tt']=secs(X.ts); X.drop(columns='ts',inplace=True)
    X=X.sort_values(['market_id','sel','tt'],kind='stable').drop_duplicates(['market_id','sel','tt'],keep='last')
    nt=0
    for e,g in X.groupby('event_id',sort=False):
        mo=g[g.mt=='MATCH_ODDS']
        if mo.empty: continue
        C['games']+=1
        mk=sorted(mo.market_id.unique())[0]; mo=mo[mo.market_id==mk]
        ev=mo.ev.iloc[0]
        if not isinstance(ev,str) or ' v ' not in ev: C['no H v A']+=1; continue
        if group(ev): C['women or youth']+=1; continue
        res=RES.get(mk)
        if res is None: C['no official']+=1; continue
        ou=g[(g.mt=='OVER_UNDER_05')]
        if ou.empty: C['no in-play OU0.5 print']+=1; continue
        ou=ou[ou.market_id==sorted(ou.market_id.unique())[0]]; ov=ou[ou.sel.astype(str).str.startswith('Over')]
        if ov.empty: C['no in-play OU0.5 Over print']+=1; continue
        ot=ov.tt.values; op=ov.ltp.values
        ip0=float(mo.tt.min()); hn,an=[s.strip() for s in ev.split(' v ',1)]
        C['games read']+=1
        for rl,sel in (('HOME',hn),('AWAY',an)):
            if sel not in res: C['runner not in result']+=1; continue
            x=mo[mo.sel==sel]; tt=x.tt.values; px=x.ltp.values
            if len(tt)<3: continue
            won=bool(res[sel])
            for E in WINS:
                t1=ip0+E*60; t0=t1-300
                seen=(last_in(tt,t0-60,t0) is not None) and (last_in(tt,t1-60,t1) is not None)
                i0=last_in(tt,t0-180,t0); i1=last_in(tt,t1-180,t1)
                if i0 is None or i1 is None: C[f'E{E} no print at t0 or t1 in 180 s']+=1; continue
                D=1/float(px[i1])-1/float(px[i0]); c=cls(D)
                if c is None: continue
                i=first_in(tt,t1+0.001,t1+120)
                if i is None: C[f'E{E} {c} no entry print']+=1; continue
                if not guard_ok(ot,op,t0,t1,float(tt[i])): C[f'E{E} {c} guard fails (goal or no OU0.5 print)']+=1; continue
                pb=fill(tt,px,i,'B'); pl=fill(tt,px,i,'L')
                if pl>50: C['price over 50']+=1; continue
                j=last_in(tt,float(tt[i])+480,float(tt[i])+720)
                if j is not None and j>i:
                    q=float(px[j]); hb=bk_out(pb,q); hl=ly_out(pl,q); hx='print'
                else:
                    hb=bk_res(pb,won); hl=ly_res(pl,won); hx='result'
                rows.append(dict(e=e,t=t1,E=E,c=c,rl=rl,seen=seen,p=pb,D=D,won=won,imp=1/pb,hx=hx,
                                 hb=hb,hl=hl,rb=bk_res(pb,won),rlay=ly_res(pl,won)))
                C[f'{c} trades'+(' SEEN by 463' if seen else ' UNSEEN')]+=1; nt+=1
    print(lo,"rows",len(X),"games",X.event_id.nunique(),"trades",nt,f"{time.time()-T0:.0f}s",flush=True); del X
con.close(); print("counts",dict(sorted(C.items())),flush=True)
TA=pd.DataFrame(rows)
if TA.empty: print("\n== SURVIVORS\nnone (no trades)"); sys.exit(0)
T=TA[~TA.seen].copy()
print('ALL windows at 180 s',len(TA),'of which UNSEEN (scored)',len(T),flush=True)
def row(nm,x,col):
    x=x.dropna(subset=[col])
    if len(x)<2: return dict(line=nm,n=len(x))
    x=x.sort_values('t'); med=x.t.median(); h=np.where(x.t<=med,1,2)
    v=x[col].astype(float).values; d=line(v,h)
    return dict(line=nm,n=d['n'],games=x.e.nunique(),per10=round(d['per10'],3),t=round(d['t'],2),h1=round(d['h1'],3),h2=round(d['h2'],3),n1=d['n1'],n2=d['n2'],
                no_top=round(np.delete(v,v.argmax()).mean(),3),won=round(x.won.mean(),3),imp=round(x.imp.mean(),3),PASS=d['PASS'])
print(f"\ntrades {len(T)}, games {T.e.nunique()}, months {pd.to_datetime(T.t,unit='s').dt.strftime('%Y-%m').nunique()}; halves by date median within each line")
print("hedge exits at a print v held to result, by class:\n",T.groupby(['c','hx']).size().unstack(fill_value=0).to_string())
print("by class and window: n, won, implied at entry\n",T.groupby(['c','E']).agg(n=('e','size'),won=('won','mean'),imp=('imp','mean')).round(3).to_string())
COLS=(('back HEDGE','hb'),('lay HEDGE','hl'),('back HOLD','rb'),('lay HOLD','rlay'))
o=[]
for c in ('SH2','SH4'):
    for E in WINS:
        x=T[(T.c==c)&(T.E==E)]
        for nm,col in COLS: o.append(row(f'{c} E{E} {nm}',x,col))
O=pd.DataFrame(o); O=O[O.n>=2]
print(f"\n== ITEM 464 (UNSEEN windows only), {len(O)} scored lines (of 32), sorted by t\n",O.sort_values('t',ascending=False).to_string(index=False))
r=[]
for c in ('SH2','SH4','DR','FLAT'):
    x=T[T.c==c]
    for nm,col in COLS: r.append(row(f'{c} all windows {nm} (pooled, correlated)',x,col))
for c in ('SH2','SH4'):
    for rl in ('HOME','AWAY'):
        x=T[(T.c==c)&(T.rl==rl)]
        r.append(row(f'{c} {rl} all windows back HEDGE',x,'hb')); r.append(row(f'{c} {rl} all windows lay HEDGE',x,'hl'))
for c in ('SH2','SH4'):
    for nm,col in COLS: r.append(row(f'ALL 180 s {c} all windows {nm} (audit, overlaps 463)',TA[TA.c==c],col))
R_=pd.DataFrame(r); print("\n-- for reading, not scored\n",R_.to_string(index=False))
T['yr']=pd.to_datetime(T.t,unit='s').dt.year
for nm in O.sort_values('t',ascending=False).head(3).line:
    p=nm.split(); x=T[(T.c==p[0])&(T.E==int(p[1][1:]))]; col=dict(COLS)[p[2]+' '+p[3]]
    print(nm,'by year',x.groupby('yr')[col].agg(['size','mean']).round(3).to_dict('index'))
P_=O[O.PASS==True]
print("\n== SURVIVORS"); print(P_.to_string(index=False) if len(P_) else "none",flush=True); print(f"total {time.time()-T0:.0f}s")
PY
