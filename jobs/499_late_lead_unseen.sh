#!/bin/bash
set -o pipefail
# 499_late_lead_unseen (Finder 2026-11-08, queue item 475, Finder's own, source a moves, from item 474's in-sample G76+ g1 n 253 +0.786 t 4.44).
# Unseen games: bf_hist_other Soccer events not in af_price_map (no af read has used them), official MO result from bf_hist_result.
# Kick-off ip0 = first in-play MO print. First goal g1 = last in-play OU0.5 print (the market closes at the goal), kept if OU1.5 prints after g1+60.
# Scorer = the side whose MO implied rose > 0.05 from its last print in [g1-600, g1-60] to its first in [g1, g1+180], the other side not.
# LATE (scored) = g1 - ip0 in [93, 106] min wall clock (about 76-89 game minutes: 15 min break + about 2 min stoppage, an approximation); CTRL = [65, 93).
# Entry = first leader print in [g1+180, g1+360] below its pre-goal print. Second goal g2 = last OU1.5 print, if MO prints 300 s past it:
# g2 <= entry-120 -> skip (known); |g2-entry| <= 120 -> lowest leader print in [entry-180, entry+120]; else lower of the entry print and the next within 120 s.
# One tick adverse, GBP 10 back, 2% on profit, official MO result, never dropped. One entry per game. Women and youth out. Halves by date median. Read only.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line,step,back_settle
from lib_official import first_in,last_in,secs,checks,group,load_results
import lib_cand; lib_cand._checks(); checks()
pd.set_option('display.width',230); pd.set_option('display.max_columns',30)
def bk(p,won):
    a=step(p,-1); return None if a<=1.01 else back_settle(a,won)
def klass(mins):
    if 93<=mins<=106: return 'LATE'
    if 65<=mins<93: return 'CTRL'
    return None
def entry_fill(tt,px,g1,pre,g2):
    """returns (price, flag) or (None, reason)"""
    i=first_in(tt,g1+180,g1+360)
    while i is not None and i<len(tt) and tt[i]<=g1+360 and not (px[i]<pre): i+=1
    if i is None or i>=len(tt) or tt[i]>g1+360: return None,'no fresh leader print in g1+180..+360'
    te=tt[i]
    if g2 is not None and g2<=te-120: return None,'second goal known before entry'
    if g2 is not None and abs(g2-te)<=120:
        w=px[(tt>=te-180)&(tt<=te+120)]; return float(w.min()),'amb'
    p=float(px[i])
    if i+1<len(tt) and tt[i+1]-te<=120: p=min(p,float(px[i+1]))
    return p,'ok'
# known answers
assert klass(93)=='LATE' and klass(106)=='LATE' and klass(92.9)=='CTRL' and klass(65)=='CTRL' and klass(64)is None and klass(107) is None
tt=np.array([0.,100.,200.,250.,400.]); px=np.array([2.0,1.9,1.5,1.4,1.3])
assert entry_fill(tt,px,0,1.8,None)==(1.4,'ok')            # first fresh print at 200 (1.5), next within 120 s at 250 (1.4) -> 1.4
assert entry_fill(tt,px,0,1.45,None)==(1.4,'ok')           # 1.5 not below 1.45; 250 is 1.4, next print 400 is 150 s later -> 1.4
assert entry_fill(tt,px,0,1.8,50)[1]=='second goal known before entry'
assert entry_fill(tt,px,0,1.8,260)==(1.4,'amb')            # window 20..320 -> 1.5,1.4 -> 1.4
assert entry_fill(tt,px,0,1.0,None)[0] is None
assert abs(bk(1.4,True)-10*0.39*0.98)<1e-9 and bk(1.4,False)==-10.0 and bk(1.02,True) is None
print("checks: OK",flush=True); T0=time.time()
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
RMO,d1=load_results(con,['MATCH_ODDS']); print("official MO",len(RMO),"dropped",d1,flush=True)
M=pd.read_sql("""SELECT DISTINCT r.event_id, r.market_id, r.market_type FROM bf_hist_result r WHERE r.sport='Soccer'
                 AND r.market_type IN ('MATCH_ODDS','OVER_UNDER_05','OVER_UNDER_15') AND NOT EXISTS (SELECT 1 FROM af_price_map m WHERE m.event_id=r.event_id)""",con)
W=M.pivot_table(index='event_id',columns='market_type',values='market_id',aggfunc='min').dropna()
W=W[W.MATCH_ODDS.isin(RMO.keys())]
print("unmapped events with MO (official), OU0.5, OU1.5 markets:",len(W),f"{time.time()-T0:.0f}s",flush=True)
C=Counter(); rows=[]
ids=list(W.index)
for i in range(0,len(ids),4000):
    sub=W.loc[ids[i:i+4000]]
    A=pd.read_sql("""SELECT market_id, max(ts) g1, min(market_time) mt FROM bf_hist_other WHERE sport='Soccer' AND market_id=ANY(%s) AND inplay GROUP BY 1""",con,params=(list(sub.OVER_UNDER_05),))
    A['dm']=(secs(A.g1)-secs(A.mt))/60
    cand=sub[sub.OVER_UNDER_05.isin(A[(A.dm>=50)&(A.dm<=125)].market_id)]
    C['events read']+=len(sub); C['OU0.5 closes 50-125 min after market time']+=len(cand)
    if cand.empty: continue
    g1m=dict(zip(A.market_id,secs(A.g1)))
    X=pd.read_sql("""SELECT market_id, event_name ev, sel, ts, ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_id=ANY(%s) AND inplay AND ltp>=1.01 AND ltp<1000""",
                  con,params=(list(cand.MATCH_ODDS)+list(cand.OVER_UNDER_15),))
    X['tt']=secs(X.ts); X.drop(columns='ts',inplace=True)
    X=X.sort_values(['market_id','sel','tt'],kind='stable').drop_duplicates(['market_id','sel','tt'],keep='last')
    by=dict(tuple(X.groupby('market_id',sort=False)))
    for e,r in cand.iterrows():
        mo=by.get(r.MATCH_ODDS); uo=by.get(r.OVER_UNDER_15)
        if mo is None or uo is None: C['no in-play MO or OU1.5']+=1; continue
        ev=mo.ev.iloc[0]
        if not isinstance(ev,str) or ' v ' not in ev: C['no H v A']+=1; continue
        if group(ev): C['women or youth']+=1; continue
        g1=g1m[r.OVER_UNDER_05]; ip0=float(mo.tt.min()); mins=(g1-ip0)/60; k=klass(mins)
        if k is None: C['g1 outside 65-106 min']+=1; continue
        if not (uo.tt>g1+60).any(): C['OU1.5 not printing after g1 (no goal or end)']+=1; continue
        hn,an=[s.strip() for s in ev.split(' v ',1)]; res=RMO[r.MATCH_ODDS]
        if hn not in res or an not in res: C['runner names not in result']+=1; continue
        S={s:(mo[mo.sel==s].tt.values,mo[mo.sel==s].ltp.values) for s in (hn,an)}
        def jump(s):
            tt,px=S[s]; a=last_in(tt,g1-600,g1-60); b=first_in(tt,g1,g1+180)
            if a is None or b is None: return None,None
            return 1/float(px[b])-1/float(px[a]),float(px[a])
        (jh,ph),(ja,pa)=jump(hn),jump(an)
        if jh is None or ja is None: C['no MO print around g1']+=1; continue
        if jh>0.05 and ja<=0.05: ld,pre=hn,ph
        elif ja>0.05 and jh<=0.05: ld,pre=an,pa
        else: C['scorer unclear']+=1; continue
        ul=float(uo.tt.max()); g2=ul if float(mo.tt.max())>ul+300 else None
        tt,px=S[ld]; p,flag=entry_fill(tt,px,g1,pre,g2)
        if p is None: C[flag]+=1; continue
        if p>50: C['price > 50']+=1; continue
        won=bool(res[ld]); b=bk(p,won)
        if b is None: C['ladder floor']+=1; continue
        C[k+' trades']+=1; C[flag]+=1
        rows.append(dict(e=e,t=g1,k=k,mins=mins,p=p,won=won,imp=1/p,rb=b,ld_home=(ld==hn)))
    print(f"  {min(i+4000,len(ids))}/{len(ids)} events | trades {len(rows)} | {time.time()-T0:.0f}s",flush=True); del X,by
print("counts",dict(sorted(C.items())),flush=True)
T=pd.DataFrame(rows)
if T.empty: print("\nSURVIVORS\nnone (no trades)"); sys.exit(0)
def row(nm,x):
    if len(x)<10: return dict(line=nm,n=len(x))
    x=x.sort_values('t'); med=x.t.median(); h=np.where(x.t<=med,1,2); v=x.rb.values; d=line(v,h)
    return dict(line=nm,n=d['n'],games=x.e.nunique(),per10=round(d['per10'],3),t=round(d['t'],2),n1=d['n1'],h1=round(d['h1'],3),n2=d['n2'],h2=round(d['h2'],3),
                won=round(x.won.mean(),3),imp=round(x.imp.mean(),3),no_top=round(np.delete(v,v.argmax()).mean(),3),PASS=d['PASS'])
L=T[T.k=='LATE']; Ct=T[T.k=='CTRL']
print(f"\ntrades {len(T)}, months {pd.to_datetime(T.t,unit='s').dt.strftime('%Y-%m').nunique()}")
O=pd.DataFrame([row('LATE back leader *',L)]); print("\n== ITEM 475 scored line\n",O.to_string(index=False))
R_=pd.DataFrame([row('CTRL 65-93 back leader',Ct),row('LATE price < 1.2',L[L.p<1.2]),row('LATE price 1.2-1.4',L[(L.p>=1.2)&(L.p<1.4)]),row('LATE price 1.4+',L[L.p>=1.4]),
                 row('LATE 93-99 min',L[L.mins<99]),row('LATE 99-106 min',L[L.mins>=99]),row('LATE home leads',L[L.ld_home]),row('LATE away leads',L[~L.ld_home])])
print("\n-- for reading, not scored\n",R_.to_string(index=False))
print("LATE by year",L.assign(yr=pd.to_datetime(L.t,unit='s').dt.year).groupby('yr').rb.agg(['size','mean']).round(3).to_dict('index'))
P_=O[O.PASS==True]
print("\nSURVIVORS"); print(P_.to_string(index=False) if len(P_) else "none",flush=True); print(f"total {time.time()-T0:.0f}s")
PY
