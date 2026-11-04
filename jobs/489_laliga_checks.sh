#!/bin/bash
set -o pipefail
# 489_laliga_checks (Finder 2026-11-04, items 36 and 39): can the numeric pass of jobs/489_laliga_00_audit.sh be explained away? Same rule and code for entries and exits. Nothing here selects a new line.
# A MAPPING: by league, does the tape agree with af? (a) FT: last Over 1.5 print <= 1.10 or >= 10 against the af total; (b) first goal: Over 1.5 at tape g-3..g-1 v g+3..g+6 shortens; (c) first print against the af kick-off.
# B CALIBRATION: by league at T 30 and 35, mean 1/price against how often Over 1.5 won, on the first print before the adverse tick.
# C STABILITY: La Liga by quarter of its games in date order and by season; by team, with the top five contributors removed; without entries where a goal lands by the fill +2; by price band.
# D COST: the real Over and Under 1.5 gap in ticks on liq_sample, La Liga and all games, at 0-0 in play; then the La Liga lines at k = 1, 2, 3, 5, 8 adverse ticks at entry.
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
def ix(p): return int(np.searchsorted(LD,round(float(p),2)-1e-9))
def step(p,k): return float(LD[min(max(ix(p)+k,0),len(LD)-1)])
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
assert ix(2.0)-ix(1.99)==1 and step(2.0,-1)==1.99 and step(3.0,1)==3.05 and abs(lay_hedge(3.05,5.0)-1.804878)<1e-5 and abs(back_hedge(2.98,2.0)-4.657426)<1e-5 and back_settle(2.98,False)==-10.0
A_=np.full(101,np.nan); A_[48]=2.0
assert abs(run('LAY_U',3.05,A_,[40],30,31,8,1)-lay_hedge(3.05,2.0))<1e-9 and run('LAY_U',3.05,A_,[40,42],30,31,8,2)==lay_settle(3.05,False)
print("checks: OK",flush=True)
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'"); cur.execute("SET statement_timeout='2400s'")
G=pd.read_sql("""SELECT m.event_id,f.fixture_id,f.league_id,f.league,f.season,f.kickoff,f.hg,f.ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL""",con)
EV=pd.read_sql("SELECT fixture_id,coalesce(minute,0) mn FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal')",con,params=(list(map(int,G.fixture_id)),))
goals=defaultdict(list)
for r in EV.itertuples(): goals[r.fixture_id].append(int(r.mn))
for k in goals: goals[k].sort()
TS=(30,35); rows=[]; mp=[]; cal=[]
for i in range(0,len(G),1000):
    sub=G.iloc[i:i+1000]
    P=pd.read_sql("SELECT event_id,event_name,minute,m,sel,ltp::float ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt='OU15' AND sel IN ('OVER','UNDER') AND minute BETWEEN 0 AND 130 AND ltp>=1.01 AND ltp<1000",con,params=(list(sub.event_id),))
    P=P.sort_values('m').drop_duplicates(['event_id','sel','minute'])
    names=P.drop_duplicates('event_id').set_index('event_id').event_name.to_dict()
    fm=P.sort_values('m').groupby('event_id').m.first().to_dict()
    px={}
    for (e,sl),x in P.groupby(['event_id','sel']):
        a=np.full(131,np.nan); a[x.minute.values]=x.ltp.values; px[(e,sl)]=a
    for g in sub.itertuples():
        gs=goals[g.fixture_id]; ft=g.hg+g.ag; o=px.get((g.event_id,'OVER'))
        rec=dict(league=g.league,league_id=g.league_id,lag=np.nan,ft_ok=np.nan,goal_move=np.nan)
        if g.event_id in fm: rec['lag']=(pd.Timestamp(fm[g.event_id]).tz_localize(None) if pd.Timestamp(fm[g.event_id]).tzinfo is None else pd.Timestamp(fm[g.event_id]).tz_convert('UTC').tz_localize(None))
        if o is not None:
            last=o[~np.isnan(o)][-1] if (~np.isnan(o)).any() else np.nan
            if not np.isnan(last) and (last<=1.10 or last>=10): rec['ft_ok']=float((last<=1.10)==(ft>=2))
            if gs and 10<=gs[0]<=80 and not any(x<=gs[0]+6 for x in gs[1:]):
                b=o[max(gs[0]-3,0):gs[0]]; c=o[gs[0]+3:gs[0]+7]
                b=b[~np.isnan(b)]; c=c[~np.isnan(c)]
                if len(b) and len(c): rec['goal_move']=c[0]/b[-1]
        ko=pd.Timestamp(g.kickoff); ko=ko.tz_convert('UTC').tz_localize(None) if ko.tzinfo is not None else ko
        rec['lag']=(rec['lag']-ko).total_seconds()/60 if not isinstance(rec['lag'],float) else np.nan
        mp.append(rec)
        for T in TS:
            if any(x<=T for x in gs): continue
            for side,sl in (('LAY_U','UNDER'),('BACK_O','OVER')):
                arr=px.get((g.event_id,sl))
                if arr is None: continue
                ent=first_print(arr,T+1,T+4)
                if ent is None: continue
                nx=first_print(arr,ent+1,ent+3); p0=arr[ent] if nx is None else (max(arr[ent],arr[nx]) if side=='LAY_U' else min(arr[ent],arr[nx]))
                early=any(T<x<=ent+2 for x in gs); h_,_,a_=str(names.get(g.event_id,'')).partition(' v '); d=dict(event_id=g.event_id,league=g.league,league_id=g.league_id,season=g.season,ko=ko,home=h_.strip(),away=a_.strip(),T=T,side=side,p=p0,raw=arr[ent],early=early,ft=ft)
                for ks in (1,2,3,5,8):
                    a=step(p0,ks) if side=='LAY_U' else step(p0,-ks)
                    if a<=1.01: d[f'g8_{ks}']=d[f's_{ks}']=np.nan; continue
                    d[f'g8_{ks}']=run(side,a,arr,gs,T,ent,8,ft); d[f's_{ks}']=run(side,a,arr,gs,T,ent,None,ft)
                rows.append(d)
    print(f"  {min(i+1000,len(G))}/{len(G)} {time.time()-T0:.0f}s",flush=True)
M=pd.DataFrame(mp); R=pd.DataFrame(rows)
print("\n== A MAPPING by league: lag = first print minus af kick-off, min; ft_ok = last Over 1.5 print agrees with the af total; move = Over 1.5 after / before the first goal; moved = share shortening >= 10%")
a=M.groupby(['league_id','league']).agg(games=('lag','size'),lag_med=('lag','median'),lag_bad=('lag',lambda s:((s<-5)|(s>20)).mean()),ft_n=('ft_ok','count'),ft_ok=('ft_ok','mean'),move_n=('goal_move','count'),move_med=('goal_move','median'),moved=('goal_move',lambda s:(s.dropna()<0.9).mean())).reset_index()
print(a[a.games>=300].sort_values('ft_ok').round(3).to_string(index=False))
print("\n== B CALIBRATION, first print, BACK_O side, by league; edge = won - implied")
c=R[R.side=='BACK_O'].assign(imp=lambda x:1/x.raw,won=lambda x:x.ft>=2)
b=c.groupby(['T','league']).agg(n=('won','size'),implied=('imp','mean'),won=('won','mean')).reset_index(); b['edge']=b.won-b.implied; b['se']=np.sqrt(b.won*(1-b.won)/b.n); b['z']=b.edge/b.se
print(b[b.n>=100].sort_values(['T','edge'],ascending=[True,False]).round(3).to_string(index=False))
print("\n== La Liga edge by season, T 30")
x=c[(c.league_id==140)&(c['T']==30)]; print(x.groupby('season').agg(n=('won','size'),implied=('imp','mean'),won=('won','mean')).round(3).to_string())
L=R[R.league_id==140].sort_values('ko')
print("\n== C STABILITY, La Liga, G8 at one tick")
for T,sd in ((30,'BACK_O'),(35,'BACK_O'),(30,'LAY_U'),(35,'LAY_U')):
    x=L[(L['T']==T)&(L.side==sd)].dropna(subset=['g8_1']).copy(); x['q']=pd.qcut(np.arange(len(x)),4,labels=['q1','q2','q3','q4'])
    v=x.g8_1
    print(f"T {T} {sd}: n {len(x)} mean {v.mean():+.3f} t {tstat(v):.2f} | quarters "+" ".join(f"{q} {g.g8_1.mean():+.2f} (n {len(g)}, {g.ko.min():%b%y}-{g.ko.max():%b%y})" for q,g in x.groupby('q',observed=True))+f" | no early goal n {int((~x.early).sum())} {x[~x.early].g8_1.mean():+.3f} t {tstat(x[~x.early].g8_1):.2f}; early n {int(x.early.sum())} {x[x.early].g8_1.mean():+.3f}")
    tm=pd.concat([x[['home','g8_1']].rename(columns={'home':'t'}),x[['away','g8_1']].rename(columns={'away':'t'})]).groupby('t').g8_1.agg(['size','sum','mean']).sort_values('sum',ascending=False)
    top=list(tm.index[:5]); keep=x[~x.home.isin(top)&~x.away.isin(top)]
    print(f"   top teams by P&L {[(t,int(tm.loc[t,'size']),round(float(tm.loc[t,'sum']),1)) for t in top]} | without them n {len(keep)} {keep.g8_1.mean():+.3f} t {tstat(keep.g8_1):.2f} | teams positive {int((tm['sum']>0).sum())} of {len(tm)}")
    x['pb']=pd.cut(x.p,[1,1.6,2,2.6,100] if sd=='BACK_O' else [1,1.7,2.2,3,100])
    print("   by price "+" ".join(f"{i} n {len(g)} {g.g8_1.mean():+.2f}" for i,g in x.groupby('pb',observed=True)))
print("\n== D COST: La Liga at k adverse ticks at entry, G8 and settle")
o=[]
for T,sd in ((30,'BACK_O'),(35,'BACK_O'),(30,'LAY_U'),(35,'LAY_U')):
    x=L[(L['T']==T)&(L.side==sd)]
    for ks in (1,2,3,5,8):
        v=x[f'g8_{ks}'].dropna(); w=x[f's_{ks}'].dropna(); a=x[x.season==2024][f'g8_{ks}'].dropna(); b_=x[x.season==2025][f'g8_{ks}'].dropna()
        o.append(dict(T=T,side=sd,k=ks,n=len(v),g8=v.mean(),t=tstat(v),h1=a.mean(),h2=b_.mean(),settle=w.mean(),t_s=tstat(w)))
print(pd.DataFrame(o).round(3).to_string(index=False))
# real gap
Lq=pd.read_sql("SELECT ts,event_name,sel,back_px::float bp,lay_px::float lp,back_sz::float bs,lay_sz::float ls FROM liq_sample WHERE mkt='OU15' AND event_name LIKE '%% v %%' AND back_px>1 AND lay_px>back_px",con)
fid=pd.read_sql("SELECT DISTINCT fixture_id FROM goal_stats_live WHERE league_id=140",con).fixture_id.tolist()
Tt=pd.read_sql("SELECT fixture_id,captured_at,home_team,away_team,minute,score_home,score_away FROM goal_timeline WHERE captured_at>=(SELECT min(ts)-interval '3 hours' FROM liq_sample) AND score_home IS NOT NULL ORDER BY captured_at",con)
con.close()
def norm(s):
    s=unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower()
    s=re.sub(r"\b(fc|cf|club|de|the|athletic|atletico|real|cd|ud|sd|rcd|ca)\b"," ",s)
    return set(w for w in re.sub(r"[^a-z0-9 ]"," ",s).split() if len(w)>2)
def sim(A,B): return len(A&B)/max(1,len(A|B))
Lq['t']=pd.to_datetime(Lq.ts,utc=True); Tt['t']=pd.to_datetime(Tt.captured_at,utc=True); Lq['side']=Lq.sel.str.upper().str.split().str[0]; Lq=Lq[Lq.side.isin(['OVER','UNDER'])]
gaps=[];
evs={e:g for e,g in Lq.groupby('event_name')}; tf={f:g for f,g in Tt.groupby('fixture_id')}
for f_,g in tf.items():
    H,A=norm(g.home_team.iloc[0]),norm(g.away_team.iloc[0]); best=None; bs=0
    for ev,e in evs.items():
        if e.t.max()<g.t.iloc[0] or e.t.min()>g.t.iloc[-1]: continue
        h_,_,a_=ev.partition(' v '); s=min(sim(norm(h_),H),sim(norm(a_),A))
        if s>bs: bs,best=s,ev
    if best is None or bs<0.3: continue
    mn=pd.to_numeric(g.minute,errors='coerce'); z=g[(mn>=25)&(mn<=45)&(g.score_home==0)&(g.score_away==0)]
    if not len(z): continue
    e=evs[best]; e=e[(e.t>=z.t.iloc[0])&(e.t<=z.t.iloc[-1])]
    if not len(e): continue
    e=e.assign(ticks=[ix(l)-ix(b) for b,l in zip(e.bp,e.lp)],liga=f_ in set(fid)); gaps.append(e)
Gp=pd.concat(gaps) if gaps else pd.DataFrame()
if len(Gp):
    print("\n== real gap in ticks, Over and Under 1.5, 0-0, 25-45', liq_sample")
    print(Gp.groupby(['liga','side']).agg(rows=('ticks','size'),games=('event_name','nunique'),touch=('bp','mean'),med=('ticks','median'),p75=('ticks',lambda s:s.quantile(.75)),p90=('ticks',lambda s:s.quantile(.9)),size_back=('bs','median'),size_lay=('ls','median')).round(2).to_string())
print(f"total {time.time()-T0:.0f}s")
PY
