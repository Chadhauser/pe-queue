#!/bin/bash
set -o pipefail
# 499_ou15_mirror (Finder 2026-11-04, queue item 60): the mirror of La Liga. Is Over 1.5 overpriced at 0-0 in League One and Ligue 2? The number 499 is reused with a new slug: 450-499 are all taken.
# RULE, same engine as jobs/489_laliga_checks.sh: 0-0 at T (30, 35) on af_events; enter at the first print in T+1..T+3 on the side's own selection, taking the worse of that print and the next, one tick adverse; one entry per game.
# SIDES: LAY_O lays Over 1.5 (liability 10); BACK_U backs Under 1.5 (stake 10). EXITS: settle at the result, or G8: first print at or after the first later goal +8, one tick adverse; a second goal by then, or no print, settles at the result. 2% commission on profit. Halves are the seasons.
# PLACEBO: every league with n >= 100, same code. FORWARD: 2026-27 results only from goal_timeline, as jobs/489_laliga_forward.sh, against each league's own two-season implied and won; no price from 2026-27 is used.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,math,time,psycopg2,pandas as pd,numpy as np
from collections import defaultdict
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
pd.set_option('display.width',240); pd.set_option('display.max_rows',300); pd.set_option('display.max_columns',30)
T0=time.time()
LD=[]
for lo,hi,st in ((1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)):
    v=lo
    while v<hi-1e-9: LD.append(round(v,2)); v+=st
LD.append(1000.0); LD=np.array(LD)
def ix(p): return int(np.searchsorted(LD,round(float(p),2)-1e-9))
def step(p,k): return float(LD[min(max(ix(p)+k,0),len(LD)-1)])
def net(x): return x*0.98 if x>0 else x
def lay_settle(a,sel_won): s=10/(a-1); return -10.0 if sel_won else net(s)
def lay_hedge(a,q): s=10/(a-1); return net(s*(1-a/step(q,-1)))
def back_settle(a,sel_won): return net(10*(a-1)) if sel_won else -10.0
def back_hedge(a,q): return net(10*(a/step(q,1)-1))
def first_print(arr,lo,hi=101):
    for m in range(max(lo,0),min(hi,len(arr))):
        if not np.isnan(arr[m]): return m
    return None
def run(side,a,arr,goals,T,ent,k,ft):
    over=ft>=2; g=[x for x in goals if x>T]
    settle=lay_settle(a,over) if side=='LAY_O' else back_settle(a,not over)
    if k is None or not g: return settle
    tgt=g[0]+k
    if sum(1 for x in goals if x<=tgt)>=2: return settle
    m=first_print(arr,max(tgt,ent+1))
    if m is None: return settle
    return lay_hedge(a,arr[m]) if side=='LAY_O' else back_hedge(a,arr[m])
def tstat(x):
    x=np.asarray(x,dtype=float); s=x.std(ddof=1) if len(x)>1 else 0
    return x.mean()/(s/len(x)**0.5) if s>0 else 0.0
def z_one(k,n,p): return (k/n-p)/math.sqrt(p*(1-p)/n)
# known answers, worked by hand
assert lay_settle(2.0,True)==-10.0 and abs(lay_settle(2.0,False)-9.8)<1e-9 and abs(lay_settle(3.0,False)-4.9)<1e-9
assert abs(back_settle(2.0,True)-9.8)<1e-9 and back_settle(2.0,False)==-10.0
assert abs(lay_hedge(3.05,5.0)-1.804878)<1e-5 and abs(back_hedge(2.98,2.0)-4.657426)<1e-5
assert abs(z_one(60,100,0.5)-2.0)<1e-9
A_=np.full(101,np.nan); A_[48]=2.0
assert abs(run('LAY_O',3.05,A_,[40],30,31,8,1)-lay_hedge(3.05,2.0))<1e-9 and run('LAY_O',3.05,A_,[40],30,31,8,1)<0   # one goal, exit at 48, Over shortened, lay loses
assert run('LAY_O',3.05,A_,[40,42],30,31,8,2)==-10.0 and run('LAY_O',3.05,A_,[],30,31,8,0)==lay_settle(3.05,False)    # second goal by the exit settles: lost; no goal settles: won
assert run('BACK_U',3.05,A_,[40,42],30,31,8,2)==-10.0 and run('BACK_U',3.05,A_,[],30,31,None,0)==back_settle(3.05,True)
B_=np.full(101,np.nan); assert run('LAY_O',3.05,B_,[40],30,31,8,1)==lay_settle(3.05,False)                            # no print at the exit: result, not dropped
print("checks: OK",flush=True)
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'"); cur.execute("SET statement_timeout='2400s'")
G=pd.read_sql("""SELECT m.event_id,f.fixture_id,f.league_id,f.league,f.season,f.kickoff,f.hg,f.ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL""",con)
print("games by season",G.groupby('season').size().to_dict(),flush=True)
EV=pd.read_sql("SELECT fixture_id,coalesce(minute,0) mn FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal')",con,params=(list(map(int,G.fixture_id)),))
goals=defaultdict(list)
for r in EV.itertuples(): goals[r.fixture_id].append(int(r.mn))
for k in goals: goals[k].sort()
TS=(30,35); rows=[]; ftchk=[]
for i in range(0,len(G),1000):
    sub=G.iloc[i:i+1000]
    P=pd.read_sql("SELECT event_id,minute,m,sel,ltp::float ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt='OU15' AND sel IN ('OVER','UNDER') AND minute BETWEEN 0 AND 130 AND ltp>=1.01 AND ltp<1000",con,params=(list(sub.event_id),))
    P=P.sort_values('m').drop_duplicates(['event_id','sel','minute'])
    px={}
    for (e,sl),x in P.groupby(['event_id','sel']):
        a=np.full(131,np.nan); a[x.minute.values]=x.ltp.values; px[(e,sl)]=a
    for g in sub.itertuples():
        gs=goals[g.fixture_id]; ft=g.hg+g.ag; o=px.get((g.event_id,'OVER'))
        if o is not None and (~np.isnan(o)).any():
            last=o[~np.isnan(o)][-1]
            if last<=1.10 or last>=10: ftchk.append((g.league,float((last<=1.10)==(ft>=2))))
        for T in TS:
            if any(x<=T for x in gs): continue
            for side,sl in (('LAY_O','OVER'),('BACK_U','UNDER')):
                arr=px.get((g.event_id,sl))
                if arr is None: continue
                ent=first_print(arr,T+1,T+4)
                if ent is None: continue
                nx=first_print(arr,ent+1,ent+3); p0=arr[ent] if nx is None else (max(arr[ent],arr[nx]) if side=='LAY_O' else min(arr[ent],arr[nx]))
                a=step(p0,1) if side=='LAY_O' else step(p0,-1)
                if a<=1.01: continue
                rows.append(dict(event_id=g.event_id,league=g.league,league_id=g.league_id,season=g.season,T=T,side=side,raw=arr[ent],ft=ft,g8=run(side,a,arr,gs,T,ent,8,ft),settle=run(side,a,arr,gs,T,ent,None,ft)))
    print(f"  {min(i+1000,len(G))}/{len(G)} {time.time()-T0:.0f}s",flush=True)
R=pd.DataFrame(rows); seasons=sorted(R.season.unique()); print("seasons",seasons)
print("\n== tape v af on the last Over 1.5 print, target leagues")
c=pd.DataFrame(ftchk,columns=['league','ok']); print(c.groupby('league').ok.agg(['size','mean']).round(3).loc[lambda d:d.index.isin(R[R.league_id.isin([41,62])].league.unique())].to_string())
L=[]
for (lg,lid,T,sd),x in R.groupby(['league','league_id','T','side']):
    for ex in ('g8','settle'):
        a=x[x.season==seasons[0]][ex]; b=x[x.season==seasons[-1]][ex]; v=x[ex]
        L.append(dict(league=lg,lid=lid,T=T,side=sd,exit=ex,n=len(v),per10=v.mean(),t=tstat(v),h1=a.mean(),n1=len(a),h2=b.mean(),n2=len(b)))
L=pd.DataFrame(L); L['PASS']=(L.n>=300)&(L.n1>=150)&(L.n2>=150)&(L.h1>0)&(L.h2>0)&(L.t>=3.5)&(L.per10>=0.15)
Pl=L[L.n>=100]; print(f"\n== PLACEBO: {Pl.league.nunique()} leagues, {len(Pl)} lines with n >= 100")
print("\n== TARGET lines: League One (41), Ligue 2 (62)")
print(L[L.lid.isin([41,62])].sort_values(['lid','T','side','exit']).round(3).to_string(index=False))
print("\n== TOP 15 by t, every league, n >= 100"); print(Pl.sort_values('t',ascending=False).head(15).round(3).to_string(index=False))
print("\n== how many leagues sit at |t| >= 2 on LAY_O g8: by T"); print(Pl[(Pl.side=='LAY_O')&(Pl.exit=='g8')].groupby('T').t.agg(n='size',over2=lambda s:int((s>=2).sum()),under2=lambda s:int((s<=-2).sum())).to_string())
C=R[R.side=='LAY_O'].assign(imp=lambda d:1/d.raw,won=lambda d:d.ft>=2); Cb=C.groupby(['league_id','league','T']).agg(n=('won','size'),implied=('imp','mean'),won=('won','mean')).reset_index()
print("\n== two-season Over 1.5 implied v won, first print"); print(Cb[Cb.league_id.isin([41,62,140])].round(3).to_string(index=False))
print("\n== FORWARD 2026-27: results only from goal_timeline; no price used")
def game(g,T):
    m=pd.to_numeric(g.minute,errors='coerce'); w=g[m>=T]
    if not len(w): return None
    r=w.iloc[0]; last=g.iloc[-1]; lm=pd.to_numeric(pd.Series([last.minute]),errors='coerce').iloc[0]
    known=str(last.status) in ('FT','AET','PEN','Match Finished','FINISHED') or (pd.notna(lm) and lm>=88)
    return (int(r.score_home)==0 and int(r.score_away)==0,int(last.score_home)+int(last.score_away),known)
t_=pd.DataFrame(dict(minute=[10,31,90],score_home=[0,0,2],score_away=[0,0,0],status=['1H','1H','FT'])); assert game(t_,30)==(True,2,True) and game(t_,95) is None
FW=[]
for lg,nm in ((41,'League One'),(62,'Ligue 2'),(140,'La Liga'),(141,'Segunda'),(135,'Serie A'),(39,'Premier League')):
    D=pd.read_sql("SELECT fixture_id,captured_at,minute,score_home,score_away,status FROM goal_timeline WHERE league_id=%s AND score_home IS NOT NULL AND score_away IS NOT NULL AND captured_at>='2026-08-01' ORDER BY fixture_id,captured_at",con,params=(lg,))
    print(f"{nm}: {D.fixture_id.nunique()} fixtures, {D.captured_at.min()} .. {D.captured_at.max()}",flush=True)
    for T in TS:
        r=[game(g,T) for _,g in D.groupby('fixture_id')]; r=[x for x in r if x is not None]; z=[x for x in r if x[0]]; kn=[x for x in z if x[2]]; n=len(kn); k=sum(1 for x in kn if x[1]>=2)
        base=Cb[(Cb.league_id==lg)&(Cb['T']==T)]
        if n==0 or not len(base): print(f"  T {T}: no games or no two-season base"); continue
        imp=float(base.implied.iloc[0]); won=float(base.won.iloc[0])
        print(f"  T {T}: reached {len(r)}, 0-0 {len(z)}, known {n}, Over 1.5 won {k} = {k/n:.3f} | two-season implied {imp:.3f} z {z_one(k,n,imp):+.2f} | two-season won {won:.3f} z {z_one(k,n,won):+.2f}",flush=True)
con.close()
S=L[L.PASS]; print(f"\n== SURVIVORS: {len(S)} of {len(L)} lines; in the target leagues {int(S.lid.isin([41,62]).sum())}")
if len(S): print(S.sort_values('t',ascending=False).round(3).to_string(index=False))
print(f"total {time.time()-T0:.0f}s")
PY
