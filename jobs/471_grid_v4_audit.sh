#!/bin/bash
set -o pipefail
# 471 (Finder 2026-11-03, queue item 19, audit of job 470's 58 numeric survivors). Same entry engine as 470. Three suspected artefacts, each tested rather than assumed:
# (1) DROPPED GAMES: 470 skipped 962 games whose af goal events disagreed with the FT score, conditioning on the outcome. Cause found by this job's first run: a wrong own-goal side flip, now removed
#     (41 true mismatches remain). They are KEPT and flagged (dirty=1): state comes from the events as given, the result from the true FT score. ALL = clean + dirty, CLEAN = dirty dropped. A real line must pass on both.
# (2) GOAL-EXIT LOOK-AHEAD: the exit minute comes from the af goal minute. If the tape clock runs behind af, the print at g+2 is a PRE-goal price and a no-goal position escapes the goal it
#     should have paid for. Test: exits NG2, NG3, NG5, NG8, NG10 (first real print at/after goal + k, else settled at the result). A real edge survives a later exit; a clock leak decays to the SETTLE value.
#     Direct check: MO DRAW backed at a level score always lengthens on the next goal, so count how often the draw at g+k is still within 25% of its entry price.
# (3) THIN-MARKET FILLS: entries are LTP +/- one tick. SETTLEx3 / x5 / x17 / x40 add that many further adverse ticks at entry (17 and 40 = median and p90 of the real BTTS YES lay gap at 10-30). liq_sample (real touch) gives the actual gap from LTP to the touch on these markets.
# FINAL PASS = standard filter on BOTH ALL and CLEAN, on an exit that does not depend on the goal-minute clock being right to within k minutes (see the report for which). grid_cells_v4 is rebuilt with these exits and a dirty column.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,time,bisect,psycopg2,psycopg2.extras,pandas as pd,numpy as np
from collections import defaultdict
from functools import lru_cache
from statistics import NormalDist
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
LAD=[]
for lo,hi,st in ((1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)):
    x=lo
    while x<hi-1e-9: LAD.append(round(x,2)); x+=st
LAD.append(1000.0); LADA=np.array(LAD)
@lru_cache(maxsize=None)
def ti(p): return int(np.searchsorted(LADA,round(p,2)-1e-9))
@lru_cache(maxsize=None)
def dn(p,k=1): return float(LADA[max(ti(p)-k,0)])
@lru_cache(maxsize=None)
def up(p,k=1): return float(LADA[min(ti(p)+k,len(LADA)-1)])
def pnl(side,p,q,won,k=1):
    if side=='B':
        a=dn(p,k)
        if a<=1.01: return None
        r=(10*(a-1) if won else -10.0) if q is None else 10*(a/up(q)-1)
    else:
        a=up(p,k); s=10/(a-1)
        r=(s if not won else -10.0) if q is None else s*(1-a/dn(q))
    return r*0.98 if r>0 else r
MK={'MO':('HOME','DRAW','AWAY'),'OU15':('OVER','UNDER'),'OU25':('OVER','UNDER'),'OU35':('OVER','UNDER'),'BTTS':('YES','NO')}
LINE={'OU15':1.5,'OU25':2.5,'OU35':3.5}
def result(mkt,sel,hg,ag):
    if mkt=='MO': return (hg>ag) if sel=='HOME' else (hg<ag) if sel=='AWAY' else hg==ag
    if mkt=='BTTS': return (hg>0 and ag>0)==(sel=='YES')
    return (hg+ag>LINE[mkt])==(sel=='OVER')
def decided(mkt,h,a):
    if mkt=='MO': return False
    if mkt=='BTTS': return h>0 and a>0
    return h+a>LINE[mkt]
def state(h,a): return f"{h}-{a}" if (h+a<3 or (h==2 and a==2) or (h==2 and a==1) or (h==1 and a==2)) and h<=2 and a<=2 else '3+'
def band(m): return '00-15' if m<15 else '15-30' if m<30 else '30-45' if m<=45 else 'HT' if m<=48 else '45-60' if m<=60 else '60-75' if m<75 else '75-90' if m<=90 else None
def favband(f): return '<1.5' if f<1.5 else '1.5-2' if f<2 else '2-3' if f<3 else '3+'
def drawband(d): return '<3' if d<3 else '3-3.6' if d<3.6 else '3.6-4.5' if d<4.5 else '4.5-5.5' if d<5.5 else '5.5+'
# known answers, worked by hand:
assert dn(2.0)==1.99 and up(2.0)==2.02 and up(1.99)==2.0 and dn(1.01)==1.01 and dn(2.0,3)==1.97 and up(1.99,3)==2.04
assert abs(pnl('B',2.0,None,True)-9.702)<1e-9 and pnl('B',2.0,None,False)==-10.0 and pnl('B',1.02,None,True) is None
assert abs(pnl('B',2.0,None,True,3)-10*0.97*0.98)<1e-9                                   # 3 ticks down from 2.00 = 1.97
assert abs(pnl('L',6.0,None,False)-10/5.2*0.98)<1e-9 and pnl('L',6.0,None,True)==-10.0
assert abs(pnl('L',6.0,None,False,3)-10/5.6*0.98)<1e-9                                   # 3 ticks up from 6.0 = 6.6, stake 10/5.6
assert abs(pnl('B',3.0,2.5,False)-1.788889)<1e-5 and abs(pnl('L',6.0,3.0,False)+2.077955)<1e-5
assert result('BTTS','NO',0,0) and result('OU25','UNDER',1,1) and result('OU25','OVER',2,1) and result('MO','DRAW',0,0) and not result('BTTS','YES',2,0)
assert decided('OU15',1,1) and not decided('OU15',1,0) and decided('BTTS',1,1) and not decided('MO',5,0)
print("ladder + P&L + settlement unit checks: OK",flush=True)
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s';")
G=pd.read_sql("""SELECT m.event_id, f.fixture_id, f.season, f.league, f.hg, f.ag FROM af_price_map m
 JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL""",con)
EV=pd.read_sql("""SELECT fixture_id, coalesce(minute,0) AS minute, is_home, type, detail FROM af_events WHERE fixture_id=ANY(%s)
 AND ((type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal')) OR (type='Card' AND detail='Red Card'))""",con,params=(list(map(int,G.fixture_id)),))
goals=defaultdict(list); reds=defaultdict(list)
for r in EV.itertuples():
    # is_home already credits the team that BENEFITS from an own goal: flipping it (as 323/453/470 and this job's first run did) gives 962 FT-score mismatches, not flipping gives 41
    if r.type=='Goal': goals[r.fixture_id].append((int(r.minute),'h' if r.is_home else 'a'))
    else: reds[r.fixture_id].append((int(r.minute),'h' if r.is_home else 'a'))
for d in (goals,reds):
    for k in d: d[k].sort()
G['ev']=[len(goals.get(f,[])) for f in G.fixture_id]; G['ft']=G.hg.astype(int)+G.ag.astype(int)
G['evh']=[sum(1 for _,s in goals.get(f,[]) if s=='h') for f in G.fixture_id]; G['eva']=G.ev-G.evh
G['dirty']=((G.evh!=G.hg.astype(int))|(G.eva!=G.ag.astype(int))).astype(int)
print("games",len(G),"| dirty",int(G.dirty.sum()),"| events < FT goals:",int((G.ev<G.ft).sum()),"| events > FT goals:",int((G.ev>G.ft).sum()),"| same total, wrong sides:",int(((G.ev==G.ft)&(G.dirty==1)).sum()))
print("mean FT goals, clean v dirty:",round(G[G.dirty==0].ft.mean(),3),round(G[G.dirty==1].ft.mean(),3),"| dirty by season:",G.groupby('season').dirty.mean().round(3).to_dict(),"| dirty with zero events:",int(((G.dirty==1)&(G.ev==0)).sum()),flush=True)
print("dirty share, top 8 leagues by share:",G.groupby('league').dirty.mean().sort_values(ascending=False).head(8).round(3).to_dict(),flush=True)
SV=pd.read_sql("SELECT * FROM grid_survivors_v3 WHERE exit='NEXTGOAL'",con)
cells=defaultdict(lambda:[0,0.0,0.0,0,0.0,0,0.0,0.0]); SK=defaultdict(int); v3c=defaultdict(lambda:[0,0.0,0.0]); v3l=defaultdict(lambda:[0,0.0,0.0])
peak=defaultdict(int); DR=defaultdict(lambda:[0,0,0,0,0]); t0=time.time(); ntr=0; ng=0
EXITS=(('SETTLE',None,1),('SETTLEx3',None,4),('SETTLEx5',None,6),('SETTLEx17',None,18),('SETTLEx40',None,41),('NG2',2,1),('NG3',3,1),('NG5',5,1),('NG8',8,1),('NG10',10,1),('P10','p10',1),('P20','p20',1),('T70','t70',1),('T80','t80',1))
SEA={2024:1,2025:2}
for i in range(0,len(G),1000):
    sub=G.iloc[i:i+1000]
    P=pd.read_sql("SELECT event_id, minute, mkt, sel, ltp::float ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt IN ('MO','OU15','OU25','OU35','BTTS') AND minute BETWEEN 0 AND 95 AND ltp>=1.01 AND ltp<1000",con,params=(list(sub.event_id),))
    px={}
    for (eid,mkt,sel),gg in P.groupby(['event_id','mkt','sel'],sort=False):
        arr=np.full(97,np.nan); arr[gg.minute.values]=gg.ltp.values; px.setdefault(eid,{})[(mkt,sel)]=arr
    del P
    for g in sub.itertuples():
        b=px.get(g.event_id)
        if not b: SK['no prices']+=1; continue
        gl=goals.get(g.fixture_id,[]); hg,ag=int(g.hg),int(g.ag); dirty=int(g.dirty); s=SEA.get(int(g.season))
        if s is None: continue
        ng+=1
        H=b.get(('MO','HOME')); A=b.get(('MO','AWAY')); D=b.get(('MO','DRAW'))
        fb='n/a' if H is None or A is None or np.isnan(H[0]) or np.isnan(A[0]) else favband(min(H[0],A[0]))
        db='n/a' if D is None or np.isnan(D[0]) else drawband(D[0])
        gm=[m for m,_ in gl]
        hc=[sum(1 for x,y in gl if x<=m-1 and y=='h') for m in range(97)]; ac=[sum(1 for x,y in gl if x<=m-1 and y=='a') for m in range(97)]
        lg=[max([x for x in gm if x<=m-1],default=-9) for m in range(97)]
        # where does the tape actually see each goal? the offset of the largest one-minute MO move in -6..+10 (clean games, goals at least 12 min apart)
        if not dirty and H is not None and A is not None:
            for gi,gmin in enumerate(gm):
                if (gi and gmin-gm[gi-1]<12) or (gi+1<len(gm) and gm[gi+1]-gmin<12): continue
                best,bo=0.0,None
                for off in range(-6,11):
                    a_,b_=gmin+off-1,gmin+off
                    if a_<0 or b_>95: continue
                    for arr in (H,A):
                        if not np.isnan(arr[a_]) and not np.isnan(arr[b_]):
                            mv=abs(np.log(arr[b_]/arr[a_]))
                            if mv>best: best,bo=mv,off
                if bo is not None and best>=0.10: peak[('1H' if gmin<=45 else '2H',bo)]+=1
        for (mkt,sel),arr in b.items():
            if sel not in MK.get(mkt,()): continue
            idx=np.flatnonzero(~np.isnan(arr)).tolist()
            if not idx: continue
            won=result(mkt,sel,hg,ag); seen=set()
            def nextp(a,b_=95):
                j=bisect.bisect_left(idx,a)
                return idx[j] if j<len(idx) and idx[j]<=b_ else None
            for m in idx:
                bd=band(m)
                if bd is None or lg[m]>m-2: continue
                st=state(hc[m],ac[m]); k=(bd,st)
                if k in seen: continue
                seen.add(k)
                if decided(mkt,hc[m],ac[m]): continue
                n1=nextp(m+1,m+2); pb=arr[m] if n1 is None else min(arr[m],arr[n1]); pl=arr[m] if n1 is None else max(arr[m],arr[n1])
                start=n1 if n1 is not None else m
                j=bisect.bisect_left(gm,m); nxt=gm[j] if j<len(gm) else None
                if mkt=='MO' and sel=='DRAW' and st in ('0-0','1-1','2-2') and bd in ('60-75','75-90') and nxt is not None and not dirty and pb<=50:
                    d=DR[bd]; d[0]+=1
                    for ii,kk in enumerate((2,5,8,10)):
                        e=nextp(max(nxt+kk,start+1))
                        if e is not None and arr[e]<=pb*1.25: d[ii+1]+=1
                for ex,par,kt in EXITS:
                    if par is None: tg=None
                    elif isinstance(par,int): tg=None if nxt is None or nxt+par>95 else nxt+par
                    elif par=='p10': tg=m+10
                    elif par=='p20': tg=m+20
                    else:
                        lim=70 if par=='t70' else 80
                        if m>=lim: continue
                        tg=lim
                    q=None
                    if tg is not None:
                        e=nextp(max(tg,start+1))
                        if e is not None: q=float(arr[e])
                    for side,p in (('B',pb),('L',pl)):
                        if p>50: continue
                        r=pnl(side,float(p),q,won,kt)
                        if r is None: continue
                        c=cells[(st,bd,mkt,sel,side,ex,fb,db,dirty)]; c[0]+=1; c[1]+=r; c[2]+=r*r; c[7]+=p; ntr+=1
                        if s==1: c[3]+=1; c[4]+=r
                        else: c[5]+=1; c[6]+=r
        # v3 NEXTGOAL re-derivation on ALL games: V3 = 323's own rule; HON = worse-of fill, 2-min goal buffer, g+2; HON8 = same at g+8
        if H is None or A is None or np.isnan(H[1]) or np.isnan(A[1]): continue
        fv=favband(min(H[1],A[1])); rl=reds.get(g.fixture_id,[]); season=int(g.season)
        for t in range(0,90,5):
            h=sum(1 for x,y in gl if x<=t and y=='h'); a=sum(1 for x,y in gl if x<=t and y=='a')
            diff=max(-2,min(2,h-a)); tot=min(3,h+a); red='none'
            for x,y in rl:
                if x<=t: red=y
            j=bisect.bisect_right(gm,t); nx=gm[j] if j<len(gm) else None
            buffered=max([x for x in gm if x<=t],default=-9)>=t
            for (mkt,sel),arr in b.items():
                if sel not in MK.get(mkt,()): continue
                p0=arr[t+1]
                if np.isnan(p0) or p0>50 or decided(mkt,h,a): continue
                won=result(mkt,sel,hg,ag)
                later=np.flatnonzero(~np.isnan(arr[t+2:t+4])); n1=t+2+int(later[0]) if len(later) else None
                def xq(a0,off):
                    if nx is None or nx+off>95: return None
                    tg=max(nx+off,a0); w=np.flatnonzero(~np.isnan(arr[tg:96]))
                    return float(arr[tg+int(w[0])]) if len(w) else None
                for side in ('B','L'):
                    tr=[('V3',float(p0),xq(t+1,2))]
                    if not buffered:
                        pw=float(p0) if n1 is None else float(min(p0,arr[n1]) if side=='B' else max(p0,arr[n1]))
                        if pw<=50:
                            st_=(n1 if n1 is not None else t+1)+1
                            tr+=[('HON',pw,xq(st_,2)),('HON8',pw,xq(st_,8))]
                    for var,pe,qe in tr:
                        r=pnl(side,pe,qe,won)
                        if r is None: continue
                        for store,key in ((v3c,(var,mkt,sel,side,t//10*10,diff,tot,red,fv,season)),(v3l,(var,mkt,sel,side,t//15*15,diff,fv,g.league,season))):
                            c=store[key]; c[0]+=1; c[1]+=r; c[2]+=r*r
    del px
    print(f"  {min(i+1000,len(G))}/{len(G)} games | priced {ng} | trades {ntr} | cells {len(cells)} | {int(time.time()-t0)}s",flush=True)
print("skips:",dict(SK),flush=True)
print("\n== WHERE THE TAPE SEES THE GOAL: share of isolated goals by offset of the largest MO move (tape minute minus af goal minute, move >= 10%)")
for hf in ('1H','2H'):
    tot=sum(peak[(hf,o)] for o in range(-6,11)) or 1
    print(hf,f"n={tot}",' '.join(f"{o:+d}:{peak[(hf,o)]/tot:.0%}" for o in range(-6,11)),"| at or after +3:",f"{sum(peak[(hf,o)] for o in range(3,11))/tot:.0%}","| after +2 = goal not yet in the g+2 print",flush=True)
print("\n== DIRECT CHECK: draw backed at a level score, next goal exists; share where the draw at g+k is STILL within 25% of entry (the goal is not in that print)")
for bd,d in DR.items(): print(bd,f"n={d[0]} g+2:{d[1]/d[0]:.1%} g+5:{d[2]/d[0]:.1%} g+8:{d[3]/d[0]:.1%} g+10:{d[4]/d[0]:.1%}",flush=True)
C=pd.DataFrame([k+tuple(v) for k,v in cells.items()],columns=['state','band','mkt','sel','side','exit','fav','draw','dirty','n','s','ss','n1','s1','n2','s2','sp'])
cur.execute("""DROP TABLE IF EXISTS grid_cells_v4; CREATE TABLE grid_cells_v4 (state TEXT, band TEXT, mkt TEXT, sel TEXT, side TEXT, exit TEXT, fav TEXT, draw TEXT, dirty INT,
  n INT, s DOUBLE PRECISION, ss DOUBLE PRECISION, n1 INT, s1 DOUBLE PRECISION, n2 INT, s2 DOUBLE PRECISION, sp DOUBLE PRECISION)""")
psycopg2.extras.execute_values(cur,"INSERT INTO grid_cells_v4 VALUES %s",C.itertuples(index=False,name=None),page_size=5000)
cur.execute("SELECT count(*) FROM grid_cells_v4"); print("grid_cells_v4 rows stored:",cur.fetchone()[0],"of",len(C),flush=True)
base=['state','band','mkt','sel','side','exit']
def roll(df):
    out=[]
    for extra,lab in (([],'base'),(['fav'],'fav'),(['draw'],'draw'),(['fav','draw'],'fav+draw')):
        x=df.groupby(base+extra,as_index=False)[['n','s','ss','n1','s1','n2','s2','sp']].sum(); x['level']=lab
        for c in ('fav','draw'):
            if c not in x: x[c]='*'
        out.append(x)
    R=pd.concat(out,ignore_index=True); R['per10']=R.s/R.n; R['sd']=np.sqrt(np.maximum(R.ss/R.n-R.per10**2,1e-9)); R['t']=R.per10/(R.sd/np.sqrt(R.n))
    R['h1']=R.s1/R.n1.replace(0,np.nan); R['h2']=R.s2/R.n2.replace(0,np.nan); R['px']=R.sp/R.n
    R['PASS']=(R.n>=300)&(R.n1>=150)&(R.n2>=150)&(R.t>=3.5)&(R.h1>0)&(R.h2>0)&(R.per10>=0.15)
    return R
RA=roll(C); RC=roll(C[C.dirty==0])
key=base+['fav','draw','level']
M=RA.merge(RC[key+['n','per10','t','h1','h2','PASS']],on=key,how='left',suffixes=('','_c')); M['BOTH']=M.PASS&M.PASS_c.fillna(False).astype(bool)
pd.set_option('display.width',260); pd.set_option('display.max_rows',300); pd.set_option('display.max_columns',40)
T=M[M.n>=300]; bonf=NormalDist().inv_cdf(1-0.05/2/max(len(T),1))
print(f"\n==== {len(M)} cells, {len(T)} at n>=300; Bonferroni t {bonf:.2f}; games {ng}, trades {ntr} ====")
print("\n== passes by exit: ALL games / CLEAN only (the 470 basis) / BOTH; share of n>=300 cells positive on ALL")
print(M.groupby('exit').agg(cells=('n',lambda v:(v>=300).sum()),pass_all=('PASS','sum'),pass_clean=('PASS_c',lambda v:v.fillna(False).astype(bool).sum()),both=('BOTH','sum'),best_t=('t',lambda v:v[M.loc[v.index,'n']>=300].max()),pos=('per10',lambda v:(v[M.loc[v.index,'n']>=300]>0).mean())).round(3).to_string())
TOP=[('2-2','75-90','MO','DRAW','B'),('1-1','75-90','MO','DRAW','B'),('1-2','75-90','OU35','OVER','L'),('1-2','75-90','OU35','UNDER','B'),('2-2','60-75','MO','DRAW','B'),('1-1','75-90','OU25','OVER','L'),('1-0','60-75','OU15','UNDER','B'),('0-0','00-15','OU25','OVER','L'),('1-2','75-90','MO','AWAY','B'),('0-0','75-90','BTTS','YES','L')]
print("\n== 470's top base survivors, per £10 (t) on ALL games, by exit")
b_=M[M.level=='base']; ORDER=['NG2','NG3','NG5','NG8','NG10','SETTLE','SETTLEx3','SETTLEx5','SETTLEx17','SETTLEx40','P10','P20']
for tp in TOP:
    x=b_[(b_.state==tp[0])&(b_.band==tp[1])&(b_.mkt==tp[2])&(b_.sel==tp[3])&(b_.side==tp[4])].set_index('exit')
    print(' '.join(tp),f"n={int(x.n.max()) if len(x) else 0}",' | '.join(f"{e} {x.per10[e]:+.2f} ({x.t[e]:.1f})" for e in ORDER if e in x.index))
LEAK=('NG2','NG3','NG5')
S=M[M.BOTH&~M.exit.isin(LEAK)].sort_values('t',ascending=False)
cols=['level','state','band','mkt','sel','side','exit','fav','draw','n','px','per10','t','n1','h1','n2','h2','n_c','per10_c','t_c','h1_c','h2_c']
print("\n== top 20 by t, n>=300, ALL games, exits not dependent on g+<=5 "); print(T[~T.exit.isin(LEAK)].sort_values('t',ascending=False).head(20)[cols].round(3).to_string(index=False))
# ---- v3
def frame(store,names): return pd.DataFrame([k+tuple(v) for k,v in store.items()],columns=names+['n','s','ss'])
F=frame(v3c,['var','mkt','sel','side','tband','diff','tot','red','fav','season']); L=frame(v3l,['var','mkt','sel','side','tband','diff','fav','league','season'])
Fg={k:v for k,v in F.groupby(['var','mkt','sel','side','tband'])}; Lg={k:v for k,v in L.groupby(['var','mkt','sel','side','tband'])}
def stat(x):
    if x.empty: return dict(n=0,mean=np.nan,t=np.nan,h1=np.nan,h2=np.nan,n1=0,n2=0)
    n=x.n.sum(); s=x.s.sum(); ss=x.ss.sum(); m=s/n; sd=max(ss/n-m*m,1e-9)**0.5
    a=x[x.season==2024]; b=x[x.season==2025]
    return dict(n=int(n),mean=m,t=m/(sd/n**0.5),h1=a.s.sum()/a.n.sum() if a.n.sum() else np.nan,h2=b.s.sum()/b.n.sum() if b.n.sum() else np.nan,n1=int(a.n.sum()),n2=int(b.n.sum()))
rows=[]
for r in SV.itertuples():
    rec=dict(level=r.level,mkt=r.mkt,sel=r.sel,side=r.side,tband=r.tband,diff=r.diff,tot=r.tot,red=r.red,fav=r.fav,league=r.league,n_v3=r.n,mean_v3=float(r.mean),t_v3=float(r.t))
    for var in ('V3','HON','HON8'):
        x=(Lg if pd.notna(r.league) else Fg).get((var,r.mkt,r.sel,r.side,r.tband),pd.DataFrame())
        if not x.empty:
            for col,val in (('diff',r.diff),('tot',r.tot),('red',r.red),('fav',r.fav),('league',r.league)):
                if pd.notna(val) and col in x: x=x[x[col]==val]
        st_=stat(x)
        for k_,v_ in st_.items(): rec[f'{k_}_{var}']=v_
        rec[f'pass_{var}']=st_['n']>=300 and st_['n1']>=150 and st_['n2']>=150 and st_['t']>=3.5 and st_['h1']>0 and st_['h2']>0 and st_['mean']>=0.15
    rows.append(rec)
Q=pd.DataFrame(rows)
print(f"\n== V3 RE-DERIVATION on ALL games: {len(Q)} NEXTGOAL survivors. Replica within £0.05 of stored on {(abs(Q.mean_V3-Q.mean_v3)<=0.05).sum()}, n within 1% on {(abs(Q.n_V3/Q.n_v3-1)<=0.01).sum()}; pass: replica {Q.pass_V3.sum()}, HON g+2 {Q.pass_HON.sum()}, HON g+8 {Q.pass_HON8.sum()}")
print(f"mean per £10 across them: stored {Q.mean_v3.mean():.3f}, replica {Q.mean_V3.mean():.3f}, HON g+2 {Q.mean_HON.mean():.3f}, HON g+8 {Q.mean_HON8.mean():.3f}")
print(Q.sort_values('t_v3',ascending=False).head(10)[['level','mkt','sel','side','tband','diff','n_v3','mean_v3','n_V3','mean_V3','mean_HON','t_HON','mean_HON8','t_HON8','pass_HON8']].round(3).to_string(index=False))
print(f"\nstill passing at g+8: {int(Q.pass_HON8.sum())}"); print(Q[Q.pass_HON8].sort_values('t_HON8',ascending=False).head(15)[['level','mkt','sel','side','tband','diff','tot','red','fav','league','n_HON8','mean_HON8','t_HON8','h1_HON8','h2_HON8']].round(3).to_string(index=False) if Q.pass_HON8.any() else "none")
# ---- real touch v LTP
L2=pd.read_sql("""SELECT mkt, sel, ltp::float ltp, back_px::float bp, lay_px::float lp, lay_sz::float ls FROM liq_sample WHERE ts>='2026-10-27' AND mkt IN ('MO','OU15','OU25','OU35','BTTS') AND minute BETWEEN 60 AND 90 AND ltp>1 AND back_px>1 AND lay_px>back_px""",con)
L2['it']=np.searchsorted(LADA,L2.ltp.round(2)-1e-9); L2['ib']=np.searchsorted(LADA,L2.bp.round(2)-1e-9); L2['il']=np.searchsorted(LADA,L2.lp.round(2)-1e-9)
L2['pxb']=pd.cut(L2.ltp,[1,2,3,5,10,30,1000],labels=['<2','2-3','3-5','5-10','10-30','30+'])
print("\n== REAL TOUCH on liq_sample, minutes 60-90: ticks from LTP to the touch you would actually hit (the engine assumes 1); median / p90")
print(L2.groupby(['mkt','sel','pxb'],observed=True).agg(n=('ltp','size'),spread_med=('il',lambda v:np.median(v-L2.loc[v.index,'ib'])),lay_gap_med=('il',lambda v:np.median(v-L2.loc[v.index,'it'])),lay_gap_p90=('il',lambda v:np.percentile(v-L2.loc[v.index,'it'],90)),back_gap_med=('ib',lambda v:np.median(L2.loc[v.index,'it']-v)),back_gap_p90=('ib',lambda v:np.percentile(L2.loc[v.index,'it']-v,90)),lay_sz_med=('ls','median')).round(1).to_string())
print(f"\n== SURVIVORS: {len(S)} (standard filter on BOTH ALL and CLEAN, exits NG8/NG10/SETTLE/SETTLEx3/x5/x17/x40/P10/P20/T70/T80), of which at or above the Bonferroni t on ALL: {(S.t>=bonf).sum()}")
print(S.head(60)[cols].round(3).to_string(index=False) if len(S) else "none")
PY
