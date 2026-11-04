#!/bin/bash
set -o pipefail
# 499_draw_22_fresh (Finder 2026-11-04, queue item 37, follow-up to 499_draw_22_late): is the numeric pass real, or stale prints from before the equaliser? In 499_draw_22_late, 56 of 739 entries above 2.6 made about 57% of the profit, and no draw at 2-2 at 75'+ is a live 8.0.
# SAME signal, fill, exits and drops as 499_draw_22_late. Filters use only what a trader sees at entry, never the result:
#   CEIL: print <= 1.25 x the median entry print of the same state, 5-minute entry band, among entries whose last goal is 20+ minutes old (that pool cannot be pre-goal).
#   PRE: print < 0.8 x the last print in tape minutes g-6..g-2 before the last goal (the price must have moved on the goal); no such print = kept.
#   FRESH = CEIL and PRE. DELAY = fill at the next print after the first (within 2 min), with no filter.
# COSTS: k = 1, 3, 4, 6 ticks adverse. The forward run measured the real back touch a median 3 ticks under LTP, so k=4 (3 + the house tick) is the honest cost of an LTP line.
# STABILITY: date quarters, age of the goal, with and without the top 5 leagues by P&L. FAMILY: grid v4 had 368,330 cells; Bonferroni at 5% needs |t| about 5.0, stated, not applied as the bar.
# FORWARD: as 499_draw_22_late, with CEIL applied to back_px, by competition.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,re,time,unicodedata,psycopg2,pandas as pd,numpy as np
from collections import defaultdict
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
pd.set_option('display.width',240); pd.set_option('display.max_rows',300); pd.set_option('display.max_columns',40)
T0=time.time()
LD=[]
for lo,hi,st in ((1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)):
    v=lo
    while v<hi-1e-9: LD.append(round(v,2)); v+=st
LD.append(1000.0); LD=np.array(LD)
def ix(p): return int(np.searchsorted(LD,round(float(p),2)-1e-9))
def dn(p,k=1): return float(LD[max(ix(p)-k,0)])
def up(p,k=1): return float(LD[min(ix(p)+k,len(LD)-1)])
def net(x): return x*0.98 if x>0 else x
def back_settle(a,won): return net(10*(a-1) if won else -10.0)
def back_hedge(a,q): return net(10*(a/up(q)-1))
def first_print(arr,lo,hi):
    for m in range(max(lo,0),min(hi,len(arr))):
        if not np.isnan(arr[m]): return m
    return None
def signal(gl,sh,sa,X,L):
    for t in range(X,90):
        h=sum(1 for m,s in gl if m<=t and s=='h'); a=sum(1 for m,s in gl if m<=t and s=='a')
        if (h,a)!=(sh,sa): continue
        if max([m for m,_ in gl if m<=t],default=-99)<=t-L: return t
    return None
def exits(arr,gl,t,ent,p,draw,k):
    a=dn(p,k)
    if a<=1.01: return None
    s=back_settle(a,draw); g=[m for m,_ in gl if m>t]
    if not g: return s,s
    m=first_print(arr,max(g[0]+8,ent+1),len(arr))
    return s,(s if m is None else back_hedge(a,float(arr[m])))
def pre_price(arr,g):
    """Last real print in tape minutes g-6..g-2, or None."""
    for m in range(g-2,g-7,-1):
        if 0<=m<len(arr) and not np.isnan(arr[m]): return float(arr[m])
    return None
def pre_ok(p,pre): return pre is None or p<0.8*pre
def band(ent): return int(ent//5*5)
def tstat(x):
    x=np.asarray(x,dtype=float); s=x.std(ddof=1) if len(x)>1 else 0
    return float(x.mean()/(s/len(x)**0.5)) if s>0 else 0.0
def norm(s):
    s=unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower()
    s=re.sub(r"\b(fc|cf|club|de|the|athletic|atletico|real|cd|ud|sd|rcd|ca)\b"," ",s)
    return set(w for w in re.sub(r"[^a-z0-9 ]"," ",s).split() if len(w)>2)
def sim(A,B): return len(A&B)/max(1,len(A|B))
def final_row(status,minute): return status in ('2H','ET') and minute is not None and minute>=85
def fwd_signal(rows,MIN=75,KNOWN=120):
    st=None
    for i,(ts,mn,h,a) in enumerate(rows):
        if (h,a)!=(2,2): st=None; continue
        if st is None: st=ts
        if ts-st>=KNOWN and mn is not None and MIN<=mn<=89: return i
    return None
# known answers, worked by hand
assert dn(3.0,4)==2.92 and abs(back_settle(1.79,True)-7.742)<1e-9 and back_settle(1.79,False)==-10.0
A_=np.full(131,np.nan); A_[66]=4.0; A_[70]=2.0
assert pre_price(A_,70)==4.0 and pre_price(A_,74)==2.0 and pre_price(A_,78) is None and pre_price(A_,67) is None
assert pre_ok(3.0,4.0) and not pre_ok(3.2,4.0) and not pre_ok(8.0,4.0) and pre_ok(8.0,None)
assert band(75)==75 and band(79)==75 and band(80)==80
B_=np.full(131,np.nan); B_[76]=3.0; B_[90]=2.0
G22=[(10,'h'),(20,'h'),(50,'a'),(70,'a')]
assert exits(B_,G22,75,76,3.0,True,1)==(back_settle(2.98,True),back_settle(2.98,True))
assert exits(B_,G22+[(80,'h')],75,76,3.0,False,1)==(-10.0,back_hedge(2.98,2.0)) and exits(B_,G22+[(85,'h')],75,76,3.0,False,1)==(-10.0,-10.0) and exits(B_,G22,75,76,1.02,True,1) is None
print("known-answer checks: OK",flush=True)
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'"); cur.execute("SET statement_timeout='2400s'")
G=pd.read_sql("""SELECT m.event_id,f.fixture_id,f.league,f.season,f.kickoff,f.hg,f.ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL""",con)
EV=pd.read_sql("SELECT fixture_id,coalesce(minute,0) mn,is_home FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal')",con,params=(list(map(int,G.fixture_id)),))
goals=defaultdict(list)
for r in EV.itertuples(): goals[r.fixture_id].append((int(r.mn),'h' if r.is_home else 'a'))
for k in goals: goals[k].sort(key=lambda z:z[0])
STATES=((2,2),(1,1)); XS=(60,70,75,80,85); KS=(1,3,4,6); rows=[]; cnt=defaultdict(int)
for i in range(0,len(G),1000):
    sub=G.iloc[i:i+1000]
    P=pd.read_sql("SELECT event_id,minute,m,sel,ltp::float ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt='MO' AND ((sel='DRAW' AND minute BETWEEN 0 AND 130) OR (sel IN ('HOME','AWAY') AND minute BETWEEN 0 AND 2)) AND ltp>=1.01 AND ltp<1000",con,params=(list(sub.event_id),))
    P=P.sort_values('m').drop_duplicates(['event_id','sel','minute'])
    D={e:x for e,x in P[P.sel=='DRAW'].groupby('event_id')}; K=P[P.sel!='DRAW'].groupby('event_id').m.min()
    for g in sub.itertuples():
        x=D.get(g.event_id)
        if x is None: cnt['no draw prints']+=1; continue
        gl=goals.get(g.fixture_id,[]); hg,ag=int(g.hg),int(g.ag)
        if sum(s=='h' for _,s in gl)!=hg or sum(s=='a' for _,s in gl)!=ag: cnt['goal events do not match FT']+=1; continue
        if g.event_id in K.index:
            lag=(pd.to_datetime(K[g.event_id],utc=True)-pd.to_datetime(g.kickoff,utc=True)).total_seconds()/60
            if not -5<=lag<=20: cnt['first print outside kick-off window']+=1; continue
        arr=np.full(131,np.nan); arr[x.minute.values]=x.ltp.values; draw=hg==ag; cnt['games used']+=1
        for sh,sa in STATES:
            for X in XS:
                t=signal(gl,sh,sa,X,2)
                if t is None: continue
                ent=first_print(arr,t+1,t+4)
                if ent is None: cnt[f'{sh}-{sa} X{X} no print']+=1; continue
                p=float(arr[ent]); last=max(m for m,_ in gl if m<=t); pre=pre_price(arr,last); e2=first_print(arr,ent+1,ent+3)
                d=dict(state=f'{sh}-{sa}',X=X,event_id=g.event_id,league=g.league,season=int(g.season),ko=g.kickoff,t=t,ent=ent,p=p,draw=draw,age=t-last,pre=pre,pre_ok=pre_ok(p,pre),p2=(float(arr[e2]) if e2 is not None else np.nan))
                ok=True
                for k in KS:
                    z=exits(arr,gl,t,ent,p,draw,k)
                    if z is None: ok=False; break
                    d[f's{k}'],d[f'g{k}']=z
                if not ok: continue
                z=exits(arr,gl,t,e2,float(arr[e2]),draw,1) if e2 is not None else None
                d['ds'],d['dg']=z if z is not None else (np.nan,np.nan)
                rows.append(d)
    print(f"  {min(i+1000,len(G))}/{len(G)} {time.time()-T0:.0f}s",flush=True)
R=pd.DataFrame(rows); assert not R.duplicated(['state','X','event_id']).any()
print("\ncounts:",dict(cnt))
R['b']=R.ent.map(band)
C=R[R.age>=20].groupby(['state','b']).p.median().rename('med').reset_index(); print("\nfresh-pool median entry print by state and band:\n",C.pivot(index='b',columns='state',values='med').round(2).to_string())
R=R.merge(C,on=['state','b'],how='left'); R['ceil_ok']=R.p<=1.25*R.med.fillna(np.inf); R['fresh']=R.ceil_ok&R.pre_ok
def line(d,c):
    d=d.dropna(subset=[c]); a=d[d.season==2024][c]; b=d[d.season==2025][c]; v=d[c]
    r=dict(n=len(v),per10=v.mean(),t=tstat(v),n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,max_win=v.max() if len(v) else np.nan)
    r['PASS']=bool(r['n']>=300 and r['n1']>=150 and r['n2']>=150 and r['t']>=3.5 and r['h1']>0 and r['h2']>0 and r['per10']>=0.15); return r
o=[]
for (st,X),d in R.groupby(['state','X']):
    for nm,f in (('ALL',d),('CEIL',d[d.ceil_ok]),('PRE',d[d.pre_ok]),('FRESH',d[d.fresh])):
        for c in ('s1','g1','s3','s4','g4','s6'): o.append(dict(state=st,X=X,filt=nm,exit=c,dropped=len(d)-len(f),**line(f,c)))
    o.append(dict(state=st,X=X,filt='DELAY',exit='ds',dropped=0,**line(d,'ds'))); o.append(dict(state=st,X=X,filt='DELAY',exit='dg',dropped=0,**line(d,'dg')))
T=pd.DataFrame(o)
print("\n== 2-2 LINES\n",T[T.state=='2-2'].round(3).to_string(index=False))
print("\n== 1-1 CONTROL, X75\n",T[(T.state=='1-1')&(T.X==75)].round(3).to_string(index=False))
B=R[(R.state=='2-2')&(R.X==75)].copy(); F=B[B.fresh].copy()
print(f"\n== X75: ALL n {len(B)} won {B.draw.mean():.4f} implied {(1/B.p).mean():.4f} | FRESH n {len(F)} won {F.draw.mean():.4f} implied {(1/F.p).mean():.4f} z {(F.draw.sum()-(1/F.p).sum())/np.sqrt(((1/F.p)*(1-1/F.p)).sum()):.2f} | dropped: price max kept {F.p.max():.2f}, dropped entries n {len(B)-len(F)} P&L sum {B[~B.fresh].s1.sum():+.0f} of {B.s1.sum():+.0f}")
F['pb']=pd.cut(F.p,[1,1.5,1.8,2.2,10]); F['ab']=pd.cut(F.age,[0,4,9,19,200],labels=['2-4','5-9','10-19','20+']); F=F.sort_values('ko'); F['q']=pd.qcut(np.arange(len(F)),4,labels=['q1','q2','q3','q4'])
for col in ('pb','ab','q'):
    print(f"\n-- FRESH by {col}\n",pd.DataFrame([dict(split=k,**line(d,'s1'),won=d.draw.mean(),imp=(1/d.p).mean(),s4=d.s4.mean()) for k,d in F.groupby(col,observed=True)]).drop(columns=['PASS']).round(3).to_string(index=False))
lg=F.groupby('league').s1.agg(['size','sum']).sort_values('sum',ascending=False); top=list(lg.index[:5]); keep=F[~F.league.isin(top)]
print(f"\nFRESH top 5 leagues by P&L {[(a,int(lg.loc[a,'size']),round(float(lg.loc[a,'sum']),1)) for a in top]}; without them {line(keep,'s1')}; leagues positive {int((lg['sum']>0).sum())} of {len(lg)}",flush=True)
try:
    Tl=pd.read_sql("SELECT fixture_id,captured_at,home_team,away_team,minute,score_home h,score_away a,status FROM goal_timeline WHERE captured_at>=(SELECT min(ts)-interval '3 hours' FROM liq_sample) AND score_home IS NOT NULL ORDER BY captured_at",con)
    Lq=pd.read_sql("SELECT ts,event_name,competition,ltp::float ltp,back_px::float bp,back_sz::float bs,lay_px::float lp FROM liq_sample WHERE mkt='MO' AND sel='DRAW' AND back_px>1 AND lay_px>back_px",con)
    E0=pd.Timestamp('2020-01-01',tz='UTC'); Lq['t']=(pd.to_datetime(Lq.ts,utc=True)-E0).dt.total_seconds(); Tl['t']=(pd.to_datetime(Tl.captured_at,utc=True)-E0).dt.total_seconds(); Tl['mn']=pd.to_numeric(Tl.minute,errors='coerce')
    evs={e:d.sort_values('t') for e,d in Lq.groupby('event_name')}; med=dict(zip(C[C.state=='2-2'].b,C[C.state=='2-2'].med)); fw=[]; un=[]
    for f_,g in Tl.groupby('fixture_id'):
        rr=[(a,None if pd.isna(b) else b,c,d) for a,b,c,d in zip(g.t,g.mn,g.h,g.a)]; i=fwd_signal(rr)
        if i is None: continue
        ts=rr[i][0]; H,A=norm(g.home_team.iloc[0]),norm(g.away_team.iloc[0]); best=None; bs=0
        for ev,e in evs.items():
            if e.t.iloc[-1]<ts or e.t.iloc[0]>ts: continue
            h_,_,a_=ev.partition(' v '); s=min(sim(norm(h_),H),sim(norm(a_),A))
            if s>bs: bs,best=s,ev
        if best is None or bs<0.3: un.append(g.home_team.iloc[0]+' v '+g.away_team.iloc[0]); continue
        e=evs[best]; w=e[(e.t>=ts)&(e.t<=ts+120)]
        if not len(w): continue
        q=w.iloc[0]; last=g.iloc[-1]
        known=final_row(last.status,None if pd.isna(last.mn) else last.mn); draw=bool(last.h==last.a) if known else False
        mn=rr[i][1]; ceil=1.25*med.get(band(mn),np.inf)
        fw.append(dict(event=best,comp=q.competition,mn=mn,bp=q.bp,gap=ix(q.lp)-ix(q.bp),size_ok=q.bs>=10,known=known,draw=draw,ceil_ok=q.bp<=ceil,s=back_settle(dn(q.bp),draw) if known else -10.0))
    W=pd.DataFrame(fw); Wf=W[W.ceil_ok]; Ws=Wf[Wf.size_ok]
    print(f"\n== FORWARD real back touch, one tick adverse: all n {len(W)} {W.s.mean():+.3f} t {tstat(W.s):.2f} draw {W.draw.mean():.3f} implied {(1/W.bp).mean():.3f} | CEIL n {len(Wf)} {Wf.s.mean():+.3f} t {tstat(Wf.s):.2f} draw {Wf.draw.mean():.3f} implied {(1/Wf.bp).mean():.3f} | CEIL and size >= £10 n {len(Ws)} {Ws.s.mean():+.3f} | unmatched {len(un)}, e.g. {un[:6]} | unknown results {int((~W.known).sum())}")
    print("gap ticks in CEIL: median",Wf.gap.median(),"| by competition n>=2:",Wf.groupby('comp').s.agg(['size','mean']).query('size>=2').round(2).to_dict('index'))
except Exception as e:
    print("FORWARD SECTION FAILED, tape result stands:",type(e).__name__,str(e)[:300],flush=True)
W2=T[T.PASS&(T.state=='2-2')&T.filt.isin(['FRESH','DELAY'])]; print(f"\n== SURVIVORS after the freshness filters: {len(W2)} lines (LTP-based, an upper bound; Bonferroni on 368,330 cells needs |t| about 5.0)"); print(W2.round(3).to_string(index=False) if len(W2) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
