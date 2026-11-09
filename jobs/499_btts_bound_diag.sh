#!/bin/bash
set -o pipefail
# 499_btts_bound_diag (Finder 2026-11-09, 01:45 UTC run, lane default/top, queue item 472's trade-level check; the code is .diag472c.py from 8 Nov,
# cut to Oct 2022-Dec 2023 so it fits the run (57 of the 87 GAP2 trades); the rule is unchanged from jobs/499_btts_bound.sh).
# Question: are the GAP2 wins prints matched as the market closes at a goal? Per trade it reads whether OU1.5 and BTTS Yes print again after entry.
# Run 9 Nov: 40 of 57 GAP2 trades were the last print on both markets (closed at entry), won 0.950 v 0.558 implied: an artefact, and not fillable.
# Usage: bash jobs/499_btts_bound_diag.sh   (about 10 min on the local DB)
cd /root/pe-queue && python3 - "$@" <<'PY'
# .diag472e.py = .diag472c.py cut to Oct 2022-Dec 2023 (time only; rule unchanged), 9 Nov
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line,step,back_settle,lay_settle
from lib_official import fill,first_in,last_in,secs,checks,group,load_results
import lib_cand; lib_cand._checks(); checks()
pd.set_option('display.width',230); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',300)
def bk_res(p,won):
    a=step(p,-1); return None if a<=1.01 else back_settle(a,won)
def ly_res(p,won): return lay_settle(step(p,1),won)
def gap(pd_,ptr,py): return 1/pd_+1/ptr-1/py
def klass(g):
    if g>=0.02: return 'GAP2'
    if g>=0: return 'CTRL'
    return None
def goal_time(ot,op,ut):
    """FIX (first run, 8 Nov): the tape's OU0.5 market closes at the first goal, so an Over print at 1.05 or under almost never exists
    (1,157 of 1,190 games on 1-10 Apr 2023). g1 = the last in-play OU0.5 Over print, kept only if OU1.5 Over prints after it
    (the game went on); a close for thinness, not a goal, is caught by the scorer check (MO implied must jump > 0.05 at g1)."""
    if len(ot)==0: return None
    g=float(ot[-1])
    return g if (ut>g).any() else None
def one_goal(ut,up,te):
    """no OU1.5 Over print at 1.10 or under at or before te, and one above 1.10 in [te-300, te]"""
    if ((ut<=te)&(up<=1.10)).any(): return False
    return bool(((ut>=te-300)&(ut<=te)&(up>1.10)).any())
# known answers, worked by hand
# Draw 4.0 (0.25) + trailer 5.0 (0.20) = 0.45; BTTS Yes 2.5 (0.40) -> GAP 0.05 GAP2; Yes 2.2 (0.4545) -> GAP -0.0045 None; Yes 2.25 (0.4444) -> 0.0056 CTRL
assert abs(gap(4.0,5.0,2.5)-0.05)<1e-9 and klass(gap(4.0,5.0,2.5))=='GAP2' and klass(gap(4.0,5.0,2.2)) is None and klass(gap(4.0,5.0,2.25))=='CTRL'
assert goal_time(np.array([10.,20.,30.]),np.array([1.5,1.4,1.3]),np.array([5.,40.]))==30. and goal_time(np.array([10.,20.]),np.array([1.5,1.4]),np.array([5.,15.])) is None and goal_time(np.array([]),np.array([]),np.array([5.])) is None
ut=np.array([100.,250.,400.]); up=np.array([1.8,1.7,1.05])
assert one_goal(ut,up,300) and not one_goal(ut,up,400) and not one_goal(ut,up,600) and not one_goal(ut,up,90)
# back 2.5 -> 2.48: wins 14.8*0.98 = 14.504; lay 2.5 -> 2.52: stake 10/1.52, wins 6.447 after 2%, loses 10
assert abs(bk_res(2.5,True)-14.8*0.98)<1e-9 and bk_res(2.5,False)==-10.0 and abs(ly_res(2.5,False)-10/1.52*0.98)<1e-9 and ly_res(2.5,True)==-10.0
print("checks: OK",flush=True); T0=time.time()
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
RMO,d1=load_results(con,['MATCH_ODDS']); RBT,d2=load_results(con,['BOTH_TEAMS_TO_SCORE'])
print("official MO",len(RMO),"dropped",d1,"BTTS",len(RBT),"dropped",d2,f"{time.time()-T0:.0f}s",flush=True)
C=Counter(); rows=[]
def chunks():
    a=pd.Timestamp(2022,10,1)
    while a<pd.Timestamp(2024,1,1):  # cut 9 Nov: Oct 2022-Dec 2023 only, 57 of the 87 GAP2 trades, to fit the run
        b=a+pd.offsets.MonthBegin(1)
        # crash fix (second run, 8 Nov): MemoryError on the 2026-09-11 10-day chunk, so 5-day chunks
        c0=a
        while c0<b:
            c1=min(c0+pd.Timedelta(days=5),b); yield str(c0.date()),str(c1.date()); c0=c1
        a=b
for lo,hi in chunks():
    X=pd.read_sql("""SELECT market_id,event_id,event_name ev,market_type mt,sel,ts,ltp::float8 ltp FROM bf_hist_other
                     WHERE sport='Soccer' AND market_type IN ('MATCH_ODDS','OVER_UNDER_05','OVER_UNDER_15','BOTH_TEAMS_TO_SCORE') AND inplay AND ltp>=1.01 AND ltp<1000
                     AND market_time>=%s AND market_time<%s AND ts>=market_time-interval '30 minutes' AND ts<=market_time+interval '150 minutes'""",con,params=(lo,hi))
    if X.empty: C['empty chunks']+=1; continue
    X['tt']=secs(X.ts); X.drop(columns='ts',inplace=True)
    X=X.sort_values(['market_id','sel','tt'],kind='stable').drop_duplicates(['market_id','sel','tt'],keep='last')
    nt=0
    for e,g in X.groupby('event_id',sort=False):
        mo=g[g.mt=='MATCH_ODDS']; bt=g[g.mt=='BOTH_TEAMS_TO_SCORE']
        if mo.empty or bt.empty: continue
        C['games with MO and BTTS in play']+=1
        mk=sorted(mo.market_id.unique())[0]; mo=mo[mo.market_id==mk]; bk_=sorted(bt.market_id.unique())[0]; bt=bt[bt.market_id==bk_]
        ev=mo.ev.iloc[0]
        if not isinstance(ev,str) or ' v ' not in ev: C['no H v A']+=1; continue
        if group(ev): C['women or youth']+=1; continue
        res=RBT.get(bk_)
        if res is None or 'Yes' not in res: C['no official BTTS']+=1; continue
        ov=g[(g.mt=='OVER_UNDER_05')&g.sel.astype(str).str.startswith('Over')]; uv=g[(g.mt=='OVER_UNDER_15')&g.sel.astype(str).str.startswith('Over')]
        if ov.empty or uv.empty: C['no OU0.5 or OU1.5 Over print']+=1; continue
        ov=ov[ov.market_id==sorted(ov.market_id.unique())[0]]; uv=uv[uv.market_id==sorted(uv.market_id.unique())[0]]
        g1=goal_time(ov.tt.values,ov.ltp.values,uv.tt.values)
        if g1 is None: C['no first goal on OU0.5']+=1; continue
        ip0=float(mo.tt.min()); hn,an=[s.strip() for s in ev.split(' v ',1)]
        S={}
        for s in (hn,an,'The Draw'):
            x=mo[mo.sel==s]; S[s]=(x.tt.values,x.ltp.values)
        if any(len(S[s][0])<2 for s in S): C['MO runner thin']+=1; continue
        def jump(s):
            tt,px=S[s]; a=last_in(tt,g1-600,g1-120); b=first_in(tt,g1,g1+180)
            if a is None or b is None: return None
            return 1/float(px[b])-1/float(px[a])
        jh,ja=jump(hn),jump(an)
        if jh is None or ja is None: C['no MO print around g1']+=1; continue
        if jh>0.05 and jh>ja: trl=an
        elif ja>0.05 and ja>jh: trl=hn
        else: C['scorer unclear']+=1; continue
        C['games read']+=1
        y=bt[bt.sel=='Yes']; yt=y.tt.values; yp=y.ltp.values; ut=uv.tt.values; up=uv.ltp.values
        won=bool(res['Yes']); got=set()
        for i in range(len(yt)):
            te=float(yt[i])
            if te<ip0+20*60 or te<g1+120: continue
            if te>ip0+80*60: break
            if not one_goal(ut,up,te): continue
            idr=last_in(S['The Draw'][0],te-60,te); itr=last_in(S[trl][0],te-60,te)
            if idr is None or itr is None: continue
            G=gap(float(S['The Draw'][1][idr]),float(S[trl][1][itr]),float(yp[i])); c=klass(G)
            if c is None or c in got: continue
            pb=fill(yt,yp,i,'B'); pl=fill(yt,yp,i,'L')
            if pl>50: continue
            got.add(c)
            ku=np.nonzero(ut>te)[0]; ky=np.nonzero(yt>te+0.001)[0]; kb=np.nonzero(ut<=te)[0]
            rows.append(dict(e=e,t=te,c=c,G=G,m=(te-ip0)/60,p=pb,won=won,imp=1/pb,rb=bk_res(pb,won),rl=ly_res(pl,won),u_next=(float(ut[ku[0]])-te) if len(ku) else None,u_last_after=(float(ut[-1])-te),u_prev=te-float(ut[kb[-1]]),y_next=(float(yt[ky[0]])-te) if len(ky) else None,y_next_px=float(yp[ky[0]]) if len(ky) else None,y_last_after=float(yt[-1])-te,dr=float(S['The Draw'][1][idr]),tr=float(S[trl][1][itr]),since_g1=te-g1))
            C[c+' trades']+=1; nt+=1
            if len(got)==2: break
    print(lo,"rows",len(X),"games",X.event_id.nunique(),"trades",nt,f"{time.time()-T0:.0f}s",flush=True); del X
con.close(); print("counts",dict(sorted(C.items())),flush=True)
T=pd.DataFrame(rows); G2=T[T.c=='GAP2']
print('GAP2 n',len(G2)); print('OU1.5 prints after entry: share',G2.u_next.notna().mean().round(3)); print('OU1.5 last print after entry, s, quantiles',G2.u_last_after.quantile([.1,.25,.5,.75,.9]).round(0).to_dict())
print('BTTS Yes prints after entry: share',G2.y_next.notna().mean().round(3),'last after, s, quantiles',G2.y_last_after.quantile([.1,.25,.5,.75,.9]).round(0).to_dict())
print('since g1, s, quantiles',G2.since_g1.quantile([.1,.5,.9]).round(0).to_dict()); print('last OU1.5 print before entry, s',G2.u_prev.quantile([.1,.5,.9]).round(0).to_dict())
G2=G2.assign(ou_live=G2.u_last_after>600)
print('by OU1.5 still printing 10+ min after entry:'); print(G2.groupby('ou_live').agg(n=('rb','size'),per10=('rb','mean'),won=('won','mean'),imp=('imp','mean'),gap=('G','median')).round(3).to_string())
print(G2[['m','p','dr','tr','G','won','since_g1','u_prev','u_last_after','y_next','y_next_px','y_last_after']].round(2).head(25).to_string()); sys.exit(0)
if T.empty: print("\n== SURVIVORS\nnone (no trades)"); sys.exit(0)
def row(nm,x,col):
    x=x.dropna(subset=[col])
    if len(x)<2: return dict(line=nm,n=len(x))
    x=x.sort_values('t'); med=x.t.median(); h=np.where(x.t<=med,1,2)
    v=x[col].astype(float).values; d=line(v,h)
    return dict(line=nm,n=d['n'],games=x.e.nunique(),per10=round(d['per10'],3),t=round(d['t'],2),h1=round(d['h1'],3),h2=round(d['h2'],3),n1=d['n1'],n2=d['n2'],
                no_top=round(np.delete(v,v.argmax()).mean(),3),won=round(x.won.mean(),3),imp=round(x.imp.mean(),3),PASS=d['PASS'])
print(f"\ntrades {len(T)}, games {T.e.nunique()}, months {pd.to_datetime(T.t,unit='s').dt.strftime('%Y-%m').nunique()}; halves by date median within each line")
G2=T[T.c=='GAP2']; CT=T[T.c=='CTRL']
O=pd.DataFrame([row('GAP2 back Yes *',G2,'rb')])
print("\n== ITEM 472 scored line\n",O.to_string(index=False))
R_=pd.DataFrame([row('CTRL (GAP 0-0.02) back Yes',CT,'rb'),row('GAP2 lay Yes (mirror)',G2,'rl'),row('CTRL lay Yes (mirror)',CT,'rl'),
                 row('GAP2 back Yes, min 20-45',G2[G2.m<=45],'rb'),row('GAP2 back Yes, min 46-80',G2[G2.m>45],'rb'),
                 row('GAP 0.05+ back Yes',G2[G2.G>=0.05],'rb'),row('GAP2 back Yes, price <= 5',G2[G2.p<=5],'rb'),row('GAP2 back Yes, price > 5',G2[G2.p>5],'rb')])
print("\n-- for reading, not scored\n",R_.to_string(index=False))
T['yr']=pd.to_datetime(T.t,unit='s').dt.year
print("GAP2 back by year",G2.assign(yr=pd.to_datetime(G2.t,unit='s').dt.year).groupby('yr').rb.agg(['size','mean']).round(3).to_dict('index'))
print("GAP quantiles (GAP2)",G2.G.quantile([.1,.5,.9]).round(3).to_dict())
P_=O[O.PASS==True]
print("\n== SURVIVORS"); print(P_.to_string(index=False) if len(P_) else "none",flush=True); print(f"total {time.time()-T0:.0f}s")
PY
