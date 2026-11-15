#!/bin/bash
set -o pipefail
# 499_ht_state_thin (Finder 2026-11-08, queue item 447, from item 446; built from jobs/499_ht_state_lines.sh, rule pushed in ca5a47f before any price). Changes only: entry window 55-62 min after the first in-play print, a no-second-half-goal guard, scored on the games item 446 dropped as half-time not clear (UNSEEN). Item 446's text follows: at the half-time break, hold the goal line one (N1) and two (N2) goals above the half-time total G to the official result, back Under or lay Under. Rule pushed in the queue (278e3c4) before any OU price was read. Read only, no tables written. Prints only, so a pass is an upper bound and earns a real-touch read on liq_sample, not a stake.
# Months: Mar 2023 to Oct 2024 and Apr to Oct 2026 as the loader holds them (Nov 2024 to Apr 2026 LISTFAIL months read as no rows). Settlement: bf_hist_result official OU winner; a game without an official result is counted and left out (coverage, not outcome).
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,re,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line,step,back_settle,lay_settle
from lib_official import bk,ly,fill,first_in,secs,checks,group
import lib_cand; lib_cand._checks(); checks()
pd.set_option('display.width',230); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',300)
OU={0.5:'OVER_UNDER_05',1.5:'OVER_UNDER_15',2.5:'OVER_UNDER_25',3.5:'OVER_UNDER_35',4.5:'OVER_UNDER_45'}
HTM=['HALF_TIME','FIRST_HALF_GOALS_05','FIRST_HALF_GOALS_15','FIRST_HALF_GOALS_25','HALF_TIME_SCORE']
def ht_goals(sel):
    """Official HALF_TIME_SCORE winner -> (total, level) or None for Any unquoted."""
    m=re.match(r'^\s*(\d+)\s*-\s*(\d+)\s*$',str(sel))
    if not m: return None
    h,a=int(m.group(1)),int(m.group(2)); return h+a,h==a
def window(ip0,tht):
    """Entry window (lo,hi) in seconds, or None. Half-time must be 46+ min after the first in-play print; entry 2+ min after half-time, 55+ min after the first in-play print, 13 min after half-time at most."""
    if tht<ip0+46*60: return None
    lo=max(tht+120,ip0+55*60); hi=tht+13*60
    return (lo,hi) if lo<=hi else None
def window2(ip0):
    """Item 447: 55 to 62 min after the first in-play print, which is at or after the kick-off."""
    return (ip0+55*60,ip0+62*60)
def no_new_goal(seen_next,entry_ts):
    """Item 447: the Over (G+0.5) must not have printed at 1.05 or under before entry."""
    return seen_next is None or seen_next>=entry_ts
def guard_ok(G,seen_ts,entry_ts):
    """For G>=1 the Over (G-0.5) line must have printed at 1.05 or under before entry; seen_ts is that first time or None."""
    return True if G==0 else (seen_ts is not None and seen_ts<entry_ts)
def band(p):
    if p is None or p!=p: return None
    return 'HIGH' if p<1.7 else ('MID' if p<=2.2 else 'LOW')
# known answers, worked by hand
assert ht_goals('2 - 1')==(3,False) and ht_goals('0 - 0')==(0,True) and ht_goals('Any unquoted') is None and ht_goals('Any Unquoted ') is None and ht_goals('1 - 1')==(2,True)
assert window(0,47*60)==(55*60,60*60) and window(0,45*60) is None and window(0,50*60)==(55*60,63*60) and window(0,46*60)==(55*60,59*60)
assert window(0,60*60)==(62*60,73*60)
assert guard_ok(0,None,10) and not guard_ok(1,None,10) and guard_ok(2,5,10) and not guard_ok(2,10,10) and not guard_ok(1,12,10)
assert window2(0)==(3300,3720) and no_new_goal(None,10) and no_new_goal(10,10) and not no_new_goal(9,10)
assert band(1.6)=='HIGH' and band(1.7)=='MID' and band(2.2)=='MID' and band(2.21)=='LOW' and band(None) is None
# Under back 3.5 -> 3.45: wins 24.5*0.98=24.01; lay 3.5 -> 3.55: stake 10/2.55, wins 3.9216*0.98
assert abs(bk(3.5,True)-24.01)<1e-9 and bk(3.5,False)==-10.0 and ly(3.5,True)==-10.0 and abs(ly(3.5,False)-10/2.55*0.98)<1e-9
print("checks: OK",flush=True); T0=time.time()
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
R=pd.read_sql("SELECT market_id,event_id,market_type,sel,status FROM bf_hist_result WHERE sport='Soccer' AND market_type=ANY(%s)",con,params=(list(OU.values())+['HALF_TIME_SCORE'],))
w=R[R.status=='WINNER'].groupby('market_id').size(); ok=set(w[w==1].index)
RES={m:dict(zip(g.sel,g.status=='WINNER')) for m,g in R[R.market_id.isin(ok)].groupby('market_id')}
H=R[(R.market_type=='HALF_TIME_SCORE')&(R.status=='WINNER')&R.market_id.isin(ok)].sort_values('market_id').drop_duplicates('event_id')
HTS=dict(zip(H.event_id,H.sel)); del R,H
print("official markets",len(RES),"events with HT score",len(HTS),f"{time.time()-T0:.0f}s",flush=True)
C=Counter(); rows=[]
def months():
    for y,ms in ((2023,range(3,13)),(2024,range(1,11)),(2026,range(4,11))):
        for m in ms:
            a=pd.Timestamp(y,m,1); yield str(a.date()),str((a+pd.offsets.MonthBegin(1)).date())
for lo,hi in months():
    A=pd.read_sql("""SELECT event_id,max(event_name) ev,min(ts) FILTER (WHERE inplay) ip0,
                     max(ts) FILTER (WHERE inplay AND market_type<>'OVER_UNDER_25') tht
                     FROM bf_hist_other WHERE sport='Soccer' AND market_type=ANY(%s) AND market_time>=%s AND market_time<%s
                     AND ts>=market_time-interval '30 minutes' AND ts<=market_time+interval '3 hours' GROUP BY 1""",con,params=(HTM+['OVER_UNDER_25'],lo,hi))
    if A.empty: print(lo,"no rows",flush=True); continue
    U=pd.read_sql("""SELECT market_id,event_id,market_type mt,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type=ANY(%s)
                     AND sel LIKE 'Under%%' AND inplay AND ltp>=1.01 AND ltp<1000 AND market_time>=%s AND market_time<%s
                     AND ts>=market_time+interval '40 minutes' AND ts<=market_time+interval '150 minutes'""",con,params=(list(OU.values()),lo,hi))
    S=pd.read_sql("""SELECT event_id,market_type mt,min(ts) t1 FROM bf_hist_other WHERE sport='Soccer' AND market_type=ANY(%s)
                     AND sel LIKE 'Over%%' AND inplay AND ltp<=1.05 AND market_time>=%s AND market_time<%s
                     AND ts>=market_time-interval '30 minutes' AND ts<=market_time+interval '150 minutes' GROUP BY 1,2""",con,params=(list(OU.values()),lo,hi))
    P=pd.read_sql("""SELECT DISTINCT ON (event_id) event_id,ltp::float8 pre FROM bf_hist_other WHERE sport='Soccer' AND market_type='OVER_UNDER_25'
                     AND sel LIKE 'Over%%' AND NOT inplay AND market_time>=%s AND market_time<%s
                     AND ts>=market_time-interval '60 minutes' AND ts<=market_time+interval '10 minutes' ORDER BY event_id,ts DESC""",con,params=(lo,hi))
    U['tt']=secs(U.ts); U=U.sort_values('tt',kind='stable').drop_duplicates(['market_id','tt'])
    S['t1']=secs(S.t1); SEEN={(e,m):t for e,m,t in zip(S.event_id,S.mt,S.t1)}; PRE=dict(zip(P.event_id,P.pre))
    UG={k:g for k,g in U.groupby(['event_id','mt'],sort=False)}
    for e,ev,ip0,tht in zip(A.event_id,A.ev,A.ip0,A.tht):
        C['games']+=1
        if not isinstance(ev,str) or ' v ' not in ev: C['no H v A']+=1; continue
        if group(ev): C['women or youth']+=1; continue
        if e not in HTS: C['no official HT score']+=1; continue
        g=ht_goals(HTS[e])
        if g is None: C['HT any unquoted']+=1; continue
        G,lev=g
        if ip0 is None or ip0!=ip0: C['no in-play prints']+=1; continue
        ip0s=float(secs(pd.Series([ip0])).iloc[0])
        thts=float(secs(pd.Series([tht])).iloc[0]) if tht is not None and tht==tht else None
        unseen=(thts is None) or (window(ip0s,thts) is None)
        C['UNSEEN' if unseen else 'seen by 446']+=1
        wnd=window2(ip0s)
        for N in (1,2):
            L=G+0.5+(N-1)
            if L>4.5: continue
            k=(e,OU[L])
            if k not in UG: C[f'N{N} no line prints']+=1; continue
            x=UG[k]; mk=sorted(x.market_id.unique())[0]; x=x[x.market_id==mk]
            if mk not in RES: C[f'N{N} no official']+=1; continue
            tt=x.tt.values; px=x.ltp.values
            i=first_in(tt,wnd[0],wnd[1])
            if i is None: C[f'N{N} no print in window']+=1; continue
            if not guard_ok(G,SEEN.get((e,OU[G-0.5])) if G>=1 else None,float(tt[i])): C[f'N{N} goal G not seen before entry']+=1; continue
            if not no_new_goal(SEEN.get((e,OU[G+0.5])),float(tt[i])): C[f'N{N} second-half goal before entry']+=1; continue
            sel=f'Under {L} Goals'
            if sel not in RES[mk]: C['sel not in result']+=1; continue
            pb=fill(tt,px,i,'B'); pl=fill(tt,px,i,'L')
            if pl>50: C['price over 50']+=1; continue
            won=RES[mk][sel]
            rows.append(dict(e=e,ev=ev,ip0=ip0s,N=N,G=G,lev=lev,band=band(PRE.get(e)),px=float(px[i]),
                             vb=bk(pb,won),vl=ly(pl,won),won=won,s60=float(tt[i])>=ip0s+3600,ent=float(tt[i])-ip0s,brk=0.0,unseen=unseen))
    print(lo,"games",len(A),"under prints",len(U),"trades",len(rows),f"{time.time()-T0:.0f}s",flush=True); del A,U,S,P,UG
con.close(); print("counts",dict(sorted(C.items())),flush=True)
TA=pd.DataFrame(rows); T=TA[TA.unseen].copy(); med=T.ip0.median(); TA['h']=np.where(TA.ip0<=med,1,2); T['h']=np.where(T.ip0<=med,1,2)
print(f"\nhalves split at {pd.to_datetime(med,unit='s')}; trades {len(T)}, games {T.e.nunique()}; entry median {T.ent.median()/60:.1f} min after first in-play print; UNSEEN only, audit on all games below")
print("by G and N: n, median price, Under won, implied\n",T.groupby(['N','G']).agg(n=('px','size'),px=('px','median'),won=('won','mean'),imp=('px',lambda s:(1/s).mean())).round(3).to_string())
def row(nm,x,col):
    x=x.dropna(subset=[col]); v=x[col].astype(float).values
    if len(v)<2: return dict(line=nm,n=len(v))
    d=line(v,x.h.values)
    return dict(line=nm,n=d['n'],games=x.e.nunique(),per10=round(d['per10'],3),t=round(d['t'],2),h1=round(d['h1'],3),h2=round(d['h2'],3),n1=d['n1'],n2=d['n2'],
                no_top=round(np.delete(v,v.argmax()).mean(),3),won=round(x.won.astype(float).mean(),3),imp=round((1/x.px).mean(),3),PASS=d['PASS'])
o=[]
for N in (1,2):
    for G in range(5):
        x=T[(T.N==N)&(T.G==G)]
        if x.empty: continue
        for col,sd in (('vb','back U'),('vl','lay U')):
            o.append(row(f'N{N} G{G} {sd} ALL',x,col))
            for b_ in ('LOW','MID','HIGH'): o.append(row(f'N{N} G{G} {sd} {b_}',x[x.band==b_],col))
            for lv,lb in ((True,'LEVEL'),(False,'NOT_LEVEL')):
                if G>0: o.append(row(f'N{N} G{G} {sd} {lb}',x[x.lev==lv],col))
O=pd.DataFrame(o); O=O[O.n>=2]
print(f"\n== ITEM 447 (UNSEEN games), {len(O)} scored lines, top 25 by t")
print(O.sort_values('t',ascending=False).head(25).to_string(index=False))
print("\n-- bottom 8 by t\n",O.sort_values('t').head(8).to_string(index=False))
c=[]
for N in (1,2):
    for col,sd in (('vb','back U'),('vl','lay U')): c.append(row(f'N{N} all G {sd}',T[T.N==N],col)); c.append(row(f'N{N} all G {sd} entry 60+ min',T[(T.N==N)&T.s60],col))
print("\n-- pooled and timing check, not scored\n",pd.DataFrame(c).to_string(index=False))
for N in (1,2):
    for col,sd in (('vb','back U'),('vl','lay U')): c.append(row(f'AUDIT all games N{N} all G {sd}',TA[TA.N==N],col))
print("\n-- audit, all games incl. those item 446 read, not scored\n",pd.DataFrame(c[-4:]).to_string(index=False))
top=O.sort_values('t',ascending=False).head(3)
print("\n-- timing check on the top 3 (entry 60+ min after the first in-play print)")
for nm in top.line:
    p=nm.split(); N=int(p[0][1]); G=int(p[1][1]); col='vb' if p[2]=='back' else 'vl'; b_=p[4]
    x=T[(T.N==N)&(T.G==G)&T.s60]
    if b_ in ('LOW','MID','HIGH'): x=x[x.band==b_]
    elif b_=='LEVEL': x=x[x.lev]
    elif b_=='NOT_LEVEL': x=x[~x.lev]
    print(row(nm+' s60',x,col))
P_=O[O.PASS==True]
print("\n== SURVIVORS"); print(P_.to_string(index=False) if len(P_) else "none",flush=True); print(f"total {time.time()-T0:.0f}s")
PY
