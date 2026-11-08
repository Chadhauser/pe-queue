#!/bin/bash
set -o pipefail
# 499_ht_break_drift (Finder 2026-11-08, queue item 459, Finder's own, source c structural): trade Match Odds and Over/Under 2.5 ACROSS the half-time
# break. Entry at the first print 1-4 min after the half-time whistle, out by the hedge at the last print 3+ min after entry and no later than
# half-time + 12 min. No game time passes in that window, so no result exposure and no settled-market case: the trade is closed before the restart.
# Rule pushed in the queue (claim commit b85ae0b) before any price was read. Read only, no tables written. Prints only, so a pass is an upper bound
# and earns a real-touch read on liq_sample, not a stake.
# Half-time = last in-play print on HALF_TIME / FIRST_HALF_GOALS_05/15/25 / HALF_TIME_SCORE, 46-60 min after the first in-play MO print, with 3+ such
# prints in the 5 min before it (a thin book that just stops printing is not read as the whistle). State from the official HALF_TIME_SCORE.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,re,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line,step,back_hedge,lay_hedge
from lib_official import fill,first_in,last_in,secs,checks,group
import lib_cand; lib_cand._checks(); checks()
pd.set_option('display.width',230); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',300)
HTM=['HALF_TIME','FIRST_HALF_GOALS_05','FIRST_HALF_GOALS_15','FIRST_HALF_GOALS_25','HALF_TIME_SCORE']
def ht_score(sel):
    m=re.match(r'^\s*(\d+)\s*-\s*(\d+)\s*$',str(sel))
    return (int(m.group(1)),int(m.group(2))) if m else None
def state(h,a):
    if h==0 and a==0: return 'S00'
    if h==a: return 'LEVEL'
    return 'LEAD1' if abs(h-a)==1 else 'LEAD2'
def ht_ok(ip0,tht,n5):
    """Half-time accepted only 46-60 min after the first in-play print, with 3+ half-time-market prints in the 5 min before it."""
    return ip0+46*60<=tht<=ip0+60*60 and n5>=3
def win_entry(tht): return (tht+60,tht+240)
def win_exit(tht,te): return (te+180,tht+720)
def role(sel,hn,an,h,a):
    if sel=='The Draw': return 'DRAW'
    if h==a: return 'HOME' if sel==hn else ('AWAY' if sel==an else None)
    lead=hn if h>a else an
    if sel not in (hn,an): return None
    return 'LEADER' if sel==lead else 'TRAILER'
def bk_out(p_in,q_out):
    """Back at the entry print one tick adverse, out by laying at the exit print one tick adverse; None if the entry is at the ladder floor."""
    a=step(p_in,-1); return None if a<=1.01 else back_hedge(a,q_out)
def ly_out(p_in,q_out):
    """Lay at the entry print one tick adverse (GBP 10 liability), out by backing at the exit print one tick adverse; None if the exit is at the floor."""
    if step(q_out,-1)<=1.01: return None
    return lay_hedge(step(p_in,1),q_out)
# known answers, worked by hand
assert ht_score('2 - 1')==(2,1) and ht_score('Any unquoted') is None and state(0,0)=='S00' and state(1,1)=='LEVEL' and state(2,1)=='LEAD1' and state(0,2)=='LEAD2'
assert ht_ok(0,47*60,3) and not ht_ok(0,45*60,9) and not ht_ok(0,61*60,9) and not ht_ok(0,50*60,2) and ht_ok(0,60*60,5)
assert win_entry(1000)==(1060,1240) and win_exit(1000,1100)==(1280,1720)
assert role('The Draw','A','B',1,0)=='DRAW' and role('A','A','B',1,0)=='LEADER' and role('B','A','B',1,0)=='TRAILER' and role('B','A','B',0,2)=='LEADER'
assert role('A','A','B',1,1)=='HOME' and role('B','A','B',0,0)=='AWAY' and role('C','A','B',1,0) is None
# back 3.0 -> 2.98, out at 3.0 lay -> 3.05: 10*(2.98/3.05-1) = -0.229508 (a loss, no commission)
assert abs(bk_out(3.0,3.0)-10*(2.98/3.05-1))<1e-9
# back 3.0 -> 2.98, out at 2.5 lay -> 2.52: 10*(2.98/2.52-1)=1.825397, after 2% 1.788889
assert abs(bk_out(3.0,2.5)-10*(2.98/2.52-1)*0.98)<1e-9
# lay 3.0 -> 3.05, stake 10/2.05=4.878049; out at 3.0 back -> 2.98: 4.878049*(1-3.05/2.98) = -0.114586
assert abs(ly_out(3.0,3.0)-(10/2.05)*(1-3.05/2.98))<1e-9
# lay 2.0 -> 2.02, stake 9.803922; out at 2.5 back -> 2.48: 9.803922*(1-2.02/2.48)=1.818468, after 2% 1.782099
assert abs(ly_out(2.0,2.5)-(10/1.02)*(1-2.02/2.48)*0.98)<1e-9
assert bk_out(1.02,1.5) is None and ly_out(2.0,1.02) is None
print("checks: OK",flush=True); T0=time.time()
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
R=pd.read_sql("SELECT market_id,event_id,sel,status FROM bf_hist_result WHERE sport='Soccer' AND market_type='HALF_TIME_SCORE'",con)
w=R[R.status=='WINNER'].groupby('market_id').size(); ok=set(w[w==1].index)
H=R[(R.status=='WINNER')&R.market_id.isin(ok)].sort_values('market_id').drop_duplicates('event_id')
HTS=dict(zip(H.event_id,H.sel)); del R,H
print("events with an official HT score",len(HTS),f"{time.time()-T0:.0f}s",flush=True)
C=Counter(); rows=[]
def months():
    a=pd.Timestamp(2022,11,1)
    while a<pd.Timestamp(2026,10,1):
        b=a+pd.offsets.MonthBegin(1)
        for c0,c1 in ((a,a+pd.Timedelta(days=10)),(a+pd.Timedelta(days=10),a+pd.Timedelta(days=20)),(a+pd.Timedelta(days=20),b)):
            yield str(c0.date()),str(c1.date())   # three chunks a month: Sep 2026 in one read ran out of memory (first run, MemoryError)
        a=b
for lo,hi in months():
    A=pd.read_sql("""WITH h AS (SELECT event_id,ts FROM bf_hist_other WHERE sport='Soccer' AND market_type=ANY(%s) AND inplay
                       AND market_time>=%s AND market_time<%s AND ts>=market_time AND ts<=market_time+interval '2 hours'),
                     m AS (SELECT event_id,max(ts) tht FROM h GROUP BY 1)
                     SELECT m.event_id,m.tht,count(*) FILTER (WHERE h.ts>=m.tht-interval '5 minutes') n5 FROM m JOIN h USING(event_id) GROUP BY 1,2""",
                  con,params=(HTM,lo,hi))
    if A.empty: print(lo,"no rows",flush=True); continue
    K=pd.read_sql("""SELECT event_id,max(event_name) ev,min(ts) ip0 FROM bf_hist_other WHERE sport='Soccer' AND market_type='MATCH_ODDS'
                     AND market_time>=%s AND market_time<%s AND inplay AND ts>=market_time-interval '30 minutes' AND ts<=market_time+interval '2 hours' GROUP BY 1""",con,params=(lo,hi))
    IP0=dict(zip(K.event_id,secs(K.ip0))); EVN=dict(zip(K.event_id,K.ev)); del K
    P=pd.read_sql("""SELECT market_id,event_id,market_type mt,sel,ts,ltp::float8 ltp FROM bf_hist_other
                     WHERE sport='Soccer' AND market_type IN ('MATCH_ODDS','OVER_UNDER_25') AND market_time>=%s AND market_time<%s
                     AND ts>=market_time+interval '40 minutes' AND ts<=market_time+interval '100 minutes' AND inplay AND ltp>=1.01 AND ltp<1000""",con,params=(lo,hi))
    P['tt']=secs(P.ts); P.drop(columns='ts',inplace=True)
    PG={k:g.sort_values('tt',kind='stable') for k,g in P.groupby(['event_id','mt','sel'],sort=False)}
    MK={}
    for (e,mt),g in P.groupby(['event_id','mt'],sort=False): MK[(e,mt)]=sorted(g.market_id.unique())[0]
    del P
    for e,tht,n5 in zip(A.event_id,A.tht,A.n5):
        C['games']+=1
        ev=EVN.get(e)
        if not isinstance(ev,str) or ' v ' not in ev: C['no MO or OU25 in-play print / no H v A']+=1; continue
        if group(ev): C['women or youth']+=1; continue
        if e not in HTS: C['no official HT score']+=1; continue
        sc=ht_score(HTS[e])
        if sc is None: C['HT any unquoted']+=1; continue
        if e not in IP0: C['no in-play MO print']+=1; continue
        thts=float(secs(pd.Series([tht])).iloc[0])
        if not ht_ok(IP0[e],thts,int(n5)): C['half-time not clear']+=1; continue
        C['games with a clear half-time']+=1
        h,a=sc; st=state(h,a); hn,an=[s.strip() for s in ev.split(' v ',1)]
        for mt,sel in (('MATCH_ODDS',hn),('MATCH_ODDS',an),('MATCH_ODDS','The Draw'),('OVER_UNDER_25','Over 2.5 Goals'),('OVER_UNDER_25','Under 2.5 Goals')):
            x=PG.get((e,mt,sel))
            if x is None: C[f'{mt} no in-play prints for a runner']+=1; continue
            if mt=='OVER_UNDER_25':
                if h+a>=3: C['OU25 passed at HT']+=1; continue
                rl='OVER' if sel.startswith('Over') else 'UNDER'
            else:
                rl=role(sel,hn,an,h,a)
                if rl is None: C['MO sel not matched']+=1; continue
            x=x[x.market_id==MK[(e,mt)]]; tt=x.tt.values; px=x.ltp.values
            i=first_in(tt,*win_entry(thts))
            if i is None: C[f'{mt} no entry print']+=1; continue
            lo_x,hi_x=win_exit(thts,float(tt[i]))
            j=last_in(tt,lo_x,hi_x)
            if j is None or j<=i: C[f'{mt} no exit print']+=1; continue
            pb=fill(tt,px,i,'B'); pl=fill(tt,px,i,'L'); q=float(px[j])
            if pl>50: C['price over 50']+=1; continue
            rows.append(dict(e=e,t=thts,st=st,mkt='MO' if mt=='MATCH_ODDS' else 'OU25',rl=rl,p0=float(px[i]),q=q,
                             vb=bk_out(pb,q),vl=ly_out(pl,q),dt=(float(tt[j])-float(tt[i]))/60,mv=q/float(px[i])-1))
    print(lo,"games",len(A),"trades",len(rows),f"{time.time()-T0:.0f}s",flush=True); del A,PG
con.close(); print("counts",dict(sorted(C.items())),flush=True)
T=pd.DataFrame(rows); med=T.t.median(); T['h']=np.where(T.t<=med,1,2)
print(f"\nhalves split at {pd.to_datetime(med,unit='s')}; trades {len(T)}, games {T.e.nunique()}; hold median {T.dt.median():.1f} min")
print("price move exit/entry-1 by market, state, role: n, median, mean, share shorter, share longer\n",
      T.groupby(['mkt','st','rl']).mv.agg(n='size',med='median',mean='mean',shorter=lambda s:(s<0).mean(),longer=lambda s:(s>0).mean()).round(4).to_string())
def row(nm,x,col):
    x=x.dropna(subset=[col]); v=x[col].astype(float).values
    if len(v)<2: return dict(line=nm,n=len(v))
    d=line(v,x.h.values)
    return dict(line=nm,n=d['n'],games=x.e.nunique(),per10=round(d['per10'],3),t=round(d['t'],2),h1=round(d['h1'],3),h2=round(d['h2'],3),n1=d['n1'],n2=d['n2'],
                no_top=round(np.delete(v,v.argmax()).mean(),3),PASS=d['PASS'])
o=[]
for (mk,st,rl),x in T.groupby(['mkt','st','rl']):
    o.append(row(f'{mk} {st} {rl} back',x,'vb')); o.append(row(f'{mk} {st} {rl} lay',x,'vl'))
O=pd.DataFrame(o); O=O[O.n>=2]
print(f"\n== ITEM 459, {len(O)} scored lines, sorted by t")
print(O.sort_values('t',ascending=False).to_string(index=False))
print("\n-- by year, the top 3 by t (reading only)")
T['yr']=pd.to_datetime(T.t,unit='s').dt.year
for nm in O.sort_values('t',ascending=False).head(3).line:
    p=nm.split(); x=T[(T.mkt==p[0])&(T.st==p[1])&(T.rl==p[2])]; col='vb' if p[3]=='back' else 'vl'
    print(nm,x.groupby('yr')[col].agg(['size','mean']).round(3).to_dict('index'))
P_=O[O.PASS==True]
print("\n== SURVIVORS"); print(P_.to_string(index=False) if len(P_) else "none",flush=True); print(f"total {time.time()-T0:.0f}s")
PY
