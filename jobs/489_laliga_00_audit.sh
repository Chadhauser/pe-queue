#!/bin/bash
set -o pipefail
# 489_laliga (Finder 2026-11-04, queue items 36 and 39, run together as 39 asks): AUDIT OF THE LA LIGA 0-0 LINE. Own code, not 474's. 450-499 is full, so the number is shared.
# RULE at 0-0, one entry per game per T: no goal with af minute <= T. T = 15, 25, 30, 35, 46, 60, 70. Entry at the first print in tape minutes T+1..T+3, filled at the worse of it and the next print within 2 min, one tick adverse. No print = no entry, counted.
# TRADES LAY_U lay OU15 Under, £10 liability (item 36); BACK_O back OU15 Over, £10 stake (item 39). 2% commission.
# EXITS G5, G8, G10 = first print at or after the first goal + k; SETTLE. No goal, a second goal by the exit (the market has passed), or no later print: settled at the FT result. Never dropped.
# CLOCK census on 150 La Liga games: tape minute runs about 2 min behind elapsed time in the first half and about 22 behind in the second (half-time), so it tracks the match clock, and af minute is compared with it directly. A goal at T+1..T+3 can land before the fill: those entries are kept, priced as they were, and counted.
# DUPLICATES about half of OU15 rows repeat (event, sel, minute); the earliest row per minute is kept and the share that differ is printed.
# OWN GOALS only totals are used, so the flip in the older jobs does not matter here.
# PLACEBO every league with n >= 100 at that T, so La Liga can be ranked. h1/h2 = season 2024/2025. One entry per game, so games are independent within a line; lines share games. x3 = three ticks at entry.
# FORWARD liq_sample La Liga fixtures (goal_stats_live league 140), real touch, at T = 30, 46, 60. Far too few for a verdict: reported as it stands.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,re,time,unicodedata,psycopg2,pandas as pd,numpy as np
from collections import defaultdict
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
pd.set_option('display.width',240); pd.set_option('display.max_rows',300); pd.set_option('display.max_columns',30)
T0=time.time()
LD=[]
for lo,hi,st in ((1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)):
    v=lo
    while v<hi-1e-9: LD.append(round(v,2)); v+=st
LD.append(1000.0); LD=np.array(LD)
def step(p,k):
    i=int(np.searchsorted(LD,round(float(p),2)-1e-9)); return float(LD[min(max(i+k,0),len(LD)-1)])
def net(x): return x*0.98 if x>0 else x
def lay_settle(a,under_won): s=10/(a-1); return net(-10.0 if under_won else s)
def lay_hedge(a,q): s=10/(a-1); return net(s*(1-a/step(q,-1)))
def back_settle(a,over_won): return net(10*(a-1) if over_won else -10.0)
def back_hedge(a,q): return net(10*(a/step(q,1)-1))
def first_print(arr,lo,hi=101):
    for m in range(max(lo,0),min(hi,len(arr))):
        if not np.isnan(arr[m]): return m
    return None
def run(side,a,arr,goals,T,ent,k,ft):
    # goals = sorted af minutes of goals; returns P&L for an entry at fill a (already adverse)
    over=ft>=2; g=[x for x in goals if x>T]
    settle=back_settle(a,over) if side=='BACK_O' else lay_settle(a,not over)
    if k is None or not g: return settle
    tgt=g[0]+k
    if sum(1 for x in goals if x<=tgt)>=2: return settle
    m=first_print(arr,max(tgt,ent+1))
    if m is None: return settle
    return back_hedge(a,arr[m]) if side=='BACK_O' else lay_hedge(a,arr[m])
def tstat(x):
    x=np.asarray(x,dtype=float); s=x.std(ddof=1) if len(x)>1 else 0
    return x.mean()/(s/len(x)**0.5) if s>0 else 0.0
def passes(n,n1,n2,t,h1,h2,m): return bool(n>=300 and n1>=150 and n2>=150 and t>=3.5 and h1>0 and h2>0 and m>=0.15)
# known answers by hand. Ladder: step(2.0,-1)=1.99, step(3.0,1)=3.05, step(3.0,-1)=2.98.
assert step(2.0,-1)==1.99 and step(3.0,1)==3.05 and step(3.0,-1)==2.98 and step(2.0,3)==2.06 and step(4.0,-3)==3.85
# Lay Under filled 3.05, stake 10/2.05=4.878049. Under loses +4.780488; wins -10. Out at back 5.0 -> 4.9: 4.878049*(1-3.05/4.9)=1.841712, net 1.804878. Out at back 2.0 -> 1.99: 4.878049*(1-3.05/1.99)=-2.598358, no commission.
assert abs(lay_settle(3.05,False)-4.780488)<1e-5 and lay_settle(3.05,True)==-10.0 and abs(lay_hedge(3.05,5.0)-1.804878)<1e-5 and abs(lay_hedge(3.05,2.0)+2.598358)<1e-5
# Back Over filled 2.98: win 19.8*.98=19.404; lose -10; out at lay 2.0 -> 2.02: 10*(2.98/2.02-1)=4.752475, net 4.657426.
assert abs(back_settle(2.98,True)-19.404)<1e-9 and back_settle(2.98,False)==-10.0 and abs(back_hedge(2.98,2.0)-4.657426)<1e-5
# run(): a print series with 2.0 at minute 48. One goal at 40, T 30, k 8: exit at 48. Goals 40 and 42: passed, settle. No goal: settle. No print after: settle. Goal before T only: settle, as there is no goal after T.
A_=np.full(101,np.nan); A_[48]=2.0
assert abs(run('LAY_U',3.05,A_,[40],30,31,8,1)-lay_hedge(3.05,2.0))<1e-9
assert run('LAY_U',3.05,A_,[40,42],30,31,8,2)==lay_settle(3.05,False)
assert run('LAY_U',3.05,A_,[],30,31,8,0)==lay_settle(3.05,True)
assert run('BACK_O',2.98,A_,[60],30,31,8,1)==back_settle(2.98,False)
assert run('BACK_O',2.98,A_,[20,60],30,31,None,2)==back_settle(2.98,True)
assert first_print(A_,0)==48 and first_print(A_,49) is None
assert passes(300,150,150,3.5,.01,.01,.15) and not passes(299,150,150,9,1,1,1) and not passes(300,149,151,9,1,1,1) and not passes(300,150,150,3.49,1,1,1) and not passes(300,150,150,9,0,1,1) and not passes(300,150,150,9,1,0,1) and not passes(300,150,150,9,1,1,.149)
print("P&L, exit logic and pass-rule checks: OK",flush=True)
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'"); cur.execute("SET statement_timeout='2400s'")
G=pd.read_sql("""SELECT m.event_id,f.fixture_id,f.league_id,f.league,f.season,f.hg,f.ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL""",con)
EV=pd.read_sql("SELECT fixture_id,coalesce(minute,0) mn FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal')",con,params=(list(map(int,G.fixture_id)),))
goals=defaultdict(list)
for r in EV.itertuples(): goals[r.fixture_id].append(int(r.mn))
for k in goals: goals[k].sort()
mis=sum(1 for r in G.itertuples() if len(goals[r.fixture_id])!=r.hg+r.ag); print(f"games {len(G)}; event goals differ from the FT total in {mis} games; those keep the FT result and may mistime an exit",flush=True)
TS=(15,25,30,35,46,60,70); EX=(('G5',5),('G8',8),('G10',10),('SETTLE',None)); rows=[]; SK=defaultdict(int); du=0; dd=0; nr=0
for i in range(0,len(G),1000):
    sub=G.iloc[i:i+1000]
    P=pd.read_sql("SELECT event_id,minute,m,sel,ltp::float ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt='OU15' AND sel IN ('OVER','UNDER') AND minute BETWEEN 0 AND 100 AND ltp>=1.01 AND ltp<1000",con,params=(list(sub.event_id),))
    nr+=len(P); s_=P.groupby(['event_id','sel','minute']).ltp.agg(['size','nunique']); du+=int((s_['size']>1).sum()); dd+=int((s_['nunique']>1).sum())
    P=P.sort_values('m').drop_duplicates(['event_id','sel','minute'])
    px={}
    for (e,sl),x in P.groupby(['event_id','sel']):
        a=np.full(101,np.nan); a[x.minute.values]=x.ltp.values; px[(e,sl)]=a
    for g in sub.itertuples():
        gs=goals[g.fixture_id]; ft=g.hg+g.ag
        for T in TS:
            if any(x<=T for x in gs): SK['not 0-0 at T']+=1; continue
            for side,sl in (('LAY_U','UNDER'),('BACK_O','OVER')):
                arr=px.get((g.event_id,sl))
                if arr is None: SK[f'no {sl} prints']+=1; continue
                ent=first_print(arr,T+1,T+4)
                if ent is None: SK[f'no {sl} print at T+1..T+3']+=1; continue
                nx=first_print(arr,ent+1,ent+3); p0=arr[ent] if nx is None else (max(arr[ent],arr[nx]) if side=='LAY_U' else min(arr[ent],arr[nx]))
                a1=step(p0,1) if side=='LAY_U' else step(p0,-1); a3=step(p0,3) if side=='LAY_U' else step(p0,-3)
                if side=='BACK_O' and (a1<=1.01 or a3<=1.01): SK['back at 1.01']+=1; continue
                early=any(T<x<=ent+2 for x in gs)
                for ex,k in EX:
                    rows.append((g.event_id,g.league_id,g.league,g.season,T,side,ex,p0,run(side,a1,arr,gs,T,ent,k,ft),run(side,a3,arr,gs,T,ent,k,ft),early,ft))
    print(f"  {min(i+1000,len(G))}/{len(G)} {time.time()-T0:.0f}s",flush=True)
print(f"OU15 rows {nr}; repeated (event,sel,minute) {du}, of which different ltp {dd}; skips {dict(SK)}",flush=True)
R=pd.DataFrame(rows,columns=['event_id','league_id','league','season','T','side','exit','p','v','x3','early','ft'])
def line(x):
    a=x[x.season==2024].v; b=x[x.season==2025].v
    return dict(n=len(x),px=x.p.mean(),mean=x.v.mean(),t=tstat(x.v),n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,x3=x.x3.mean(),maxwin=x.v.max(),ex_top=(x.v.sum()-x.v.max())/max(len(x)-1,1),early=x.early.mean(),over_won=(x.ft>=2).mean())
rs=[]
for (lg,nm,T,sd,ex),x in R.groupby(['league_id','league','T','side','exit']): rs.append(dict(league_id=lg,league=nm,T=T,side=sd,exit=ex,**line(x)))
for (T,sd,ex),x in R.groupby(['T','side','exit']): rs.append(dict(league_id=0,league='ALL',T=T,side=sd,exit=ex,**line(x)))
O=pd.DataFrame(rs); O['PASS']=[l!=0 and passes(a,b,c,d,e,f,g) for l,a,b,c,d,e,f,g in zip(O.league_id,O.n,O.n1,O.n2,O.t,O.h1,O.h2,O['mean'])]
show=['T','side','exit','n','px','mean','t','n1','h1','n2','h2','x3','ex_top','over_won','early','PASS']
print("\n== LA LIGA, every line"); print(O[O.league_id==140].sort_values(['side','T','exit'])[show].round(3).to_string(index=False))
print("\n== ALL LEAGUES together"); print(O[(O.league_id==0)&O.exit.isin(['G8','SETTLE'])].sort_values(['side','T','exit'])[show].round(3).to_string(index=False))
print("\n== CONTROLS at G8 and settle, LAY_U and BACK_O, Segunda and the other four top leagues")
print(O[O.league_id.isin([141,39,61,78,135])&O.exit.isin(['G8','SETTLE'])&O['T'].isin([30,46,60])].sort_values(['side','T','exit','league_id'])[['league']+show].round(3).to_string(index=False))
print("\n== PLACEBO: La Liga's rank by mean among leagues with n >= 100 at that T, exit and side; lg_n = leagues; lg_pos = leagues with a positive mean; both_pos = leagues positive in both seasons; lgs_t35 = leagues at t >= 3.5")
pl=[]
for (T,sd,ex),x in O[(O.league_id!=0)&(O.n>=100)].groupby(['T','side','exit']):
    x=x.sort_values('mean',ascending=False).reset_index(drop=True); y=x[x.league_id==140]
    if len(y): pl.append(dict(T=T,side=sd,exit=ex,lg_n=len(x),rank=int(y.index[0])+1,mean=float(y['mean'].iloc[0]),t=float(y.t.iloc[0]),best=x.league.iloc[0],best_mean=float(x['mean'].iloc[0]),lg_pos=int((x['mean']>0).sum()),both_pos=int(((x.h1>0)&(x.h2>0)).sum()),lgs_t35=int((x.t>=3.5).sum())))
print(pd.DataFrame(pl).sort_values(['side','T','exit']).round(3).to_string(index=False))
print("\n== CHOOSE ON 2024, SCORE ON 2025: leagues ranked on 2024 alone (n1 >= 50), La Liga's 2024 rank, and the 2025 mean of the league that was top in 2024 and of the top three together; all = 2025 mean of every league with n1 >= 50")
ch=[]
for (T,sd,ex),x in R[R.exit.isin(['G8','SETTLE'])].groupby(['T','side','exit']):
    a=x[x.season==2024].groupby('league').v.agg(['size','mean']); a=a[a['size']>=50].sort_values('mean',ascending=False)
    if len(a)<5: continue
    y=x[x.season==2025]; top=list(a.index[:3]); t3=y[y.league.isin(top)].v
    ch.append(dict(T=T,side=sd,exit=ex,lgs=len(a),liga_rank=(list(a.index).index('La Liga')+1) if 'La Liga' in a.index else -1,top=top[0],top_24=a['mean'].iloc[0],top_25=y[y.league==top[0]].v.mean(),t_top=tstat(y[y.league==top[0]].v),top3_25=t3.mean(),t_top3=tstat(t3),n_top3=len(t3),all_25=y[y.league.isin(a.index)].v.mean()))
print(pd.DataFrame(ch).sort_values(['side','T','exit']).round(3).to_string(index=False))
print("\n== La Liga by half-season windows, LAY_U T=30 G8: is it one spell?")
x=R[(R.league_id==140)&(R['T']==30)&(R.side=='LAY_U')&(R.exit=='G8')]; print(x.groupby('season').agg(n=('v','size'),mean=('v','mean'),over_won=('ft',lambda s:(s>=2).mean()),px=('p','mean')).round(3).to_string())
# forward
print("\n== FORWARD on the real touch, La Liga, liq_sample",flush=True)
fid=pd.read_sql("SELECT DISTINCT fixture_id FROM goal_stats_live WHERE league_id=140",con).fixture_id.tolist()
T_=pd.read_sql("SELECT fixture_id,captured_at,home_team,away_team,minute,score_home,score_away,status FROM goal_timeline WHERE fixture_id=ANY(%s) AND score_home IS NOT NULL ORDER BY fixture_id,captured_at",con,params=(list(map(int,fid)),)) if fid else pd.DataFrame()
L=pd.read_sql("SELECT ts,event_name,sel,back_px::float bp,lay_px::float lp FROM liq_sample WHERE mkt='OU15' AND event_name LIKE '%% v %%' AND back_px>1 AND lay_px>back_px AND ts>=(SELECT min(ts) FROM liq_sample)",con)
con.close()
def norm(s):
    s=unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower()
    s=re.sub(r"\b(fc|cf|club|de|the|athletic|atletico|real|cd|ud|sd|rcd|ca)\b"," ",s)
    return set(w for w in re.sub(r"[^a-z0-9 ]"," ",s).split() if len(w)>2)
def sim(A,B): return len(A&B)/max(1,len(A|B))
fr=[]
if len(T_):
    L['t']=pd.to_datetime(L.ts,utc=True); L['side']=L.sel.str.upper().str.split().str[0]; L=L[L.side.isin(['OVER','UNDER'])]; T_['t']=pd.to_datetime(T_.captured_at,utc=True)
    evs={ev:g for ev,g in L.groupby('event_name')}
    for f_,g in T_.groupby('fixture_id'):
        g=g.sort_values('t')
        if g.t.iloc[-1]<L.t.min(): continue
        H,A=norm(g.home_team.iloc[0]),norm(g.away_team.iloc[0]); best=None; bs=0
        for ev,e in evs.items():
            if e.t.max()<g.t.iloc[0] or e.t.min()>g.t.iloc[-1]: continue
            h_,_,a_=ev.partition(' v '); s=min(sim(norm(h_),H),sim(norm(a_),A))
            if s>bs: bs,best=s,ev
        if best is None or bs<0.3: SK['forward, no recorder game']+=1; continue
        e=evs[best]; fh=int(g.score_home.iloc[-1]); fa=int(g.score_away.iloc[-1]); ft=fh+fa; mn=pd.to_numeric(g.minute,errors='coerce'); tot=(g.score_home.astype(int)+g.score_away.astype(int))
        known=str(g.status.iloc[-1]) in ('FT','AET','PEN','Match Finished','FINISHED') or (pd.notna(mn.iloc[-1]) and mn.iloc[-1]>=88)
        for Tf in (30,46,60):
            w=g[(mn>=Tf+1)]
            if not len(w): continue
            t0=w.t.iloc[0]
            if tot[g.t<=t0].iloc[-1]!=0: continue
            for side,sl in (('LAY_U','UNDER'),('BACK_O','OVER')):
                x=e[e.side==sl].sort_values('t'); x=x[x.t>=t0]
                if not len(x) or (x.t.iloc[0]-t0).total_seconds()>90: SK['forward, no touch within 90 s']+=1; continue
                if side=='LAY_U': v=lay_settle(step(x.lp.iloc[0],1),ft<2); px=x.lp.iloc[0]
                else: v=back_settle(step(x.bp.iloc[0],-1),ft>=2); px=x.bp.iloc[0]
                fr.append(dict(game=best[:34],T=Tf,side=side,touch=px,ft=ft,known=known,settle=v if known else -10.0))
print(f"forward skips {dict(SK)}")
if fr:
    F=pd.DataFrame(fr); print(F.groupby(['side','T']).agg(n=('settle','size'),touch=('touch','mean'),over_won=('ft',lambda s:(s>=2).mean()),settle=('settle','mean')).round(3).to_string())
else: print("no forward entries")
S=O[O.PASS].sort_values('t',ascending=False)
print(f"\n== TOP 15 single leagues by t, n>=100"); print(O[(O.league_id!=0)&(O.n>=100)].sort_values('t',ascending=False).head(15)[['league']+show].round(3).to_string(index=False))
print(f"\n{len(O[O.league_id!=0])} single-league lines")
print(f"\n== SURVIVORS: {len(S)}"); print(S[['league']+show].round(3).to_string(index=False) if len(S) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
