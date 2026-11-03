#!/bin/bash
set -o pipefail
# SUPERSEDED BY jobs/471: this run's 58 survivors are artefacts. It drops 962 games on a wrong own-goal flip and trusts the g+2 exit print. Kept as the record of what was run.
# 470 (Finder 2026-11-03, queue item 19 "In-play grid v4"): bf_hist_price MO/OU15/OU25/OU35/BTTS x score state (0-0,1-0,0-1,1-1,2-0,0-2,2-1,1-2,2-2,3+)
# x minute band (0-15,15-30,30-45,HT=46-48,45-60=49-60,60-75,75-90) x back/lay x exits (next goal +2, +10, +20, 70', 80', settle) x pre-match favourite band x draw band.
# ENTRY: first real print in the band with the game in that state. State = goals at minutes <= print minute - 1 (what could be known), and the last known goal must be at
#   least 2 minutes old so the price has settled. A goal AT the print minute is NOT dropped (dropping it is look-ahead; item 14 showed that fakes t 6). Fill = worse of that print
#   and the next real print within 2 minutes, one tick adverse (exact ladder). One entry per game per selection per state per band. Price > 50 not traded (counted).
# EXIT: first real print at/after the target minute and after the fill. No print to 95' = settled at the RESULT, never dropped. T70/T80 only for entries before that minute.
#   No next goal = settled at the result. A selection already decided at entry is not traded. ltp>=1.01 kept. £10 risk, 2% commission. Halves = season 2024 v 2025.
# V3 RE-DERIVATION: every NEXTGOAL row of grid_survivors_v3 is recomputed twice: V3 = job 323's own entry (state at t, fill at the print at t+1, no fill slippage, no goal buffer, 5-min
#   entries, two per 10-min band), HON = same cell with the worse-of fill and the 2-minute goal buffer.
# ALIGNMENT: mean |log move| in MO by minute offset to the af goal minute, so a clock mismatch between tape and af goal minutes is visible rather than assumed away.
# The same game appears in many cells, so cells are not independent; with this many cells some will pass by chance: the Bonferroni t is printed. Table grid_cells_v4.
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
def dn(p): return float(LADA[max(int(np.searchsorted(LADA,round(p,2)-1e-9))-1,0)])
@lru_cache(maxsize=None)
def up(p): return float(LADA[min(int(np.searchsorted(LADA,round(p,2)-1e-9))+1,len(LADA)-1)])
def pnl(side,p,q,won):
    if side=='B':
        a=dn(p)
        if a<=1.01: return None
        r=(10*(a-1) if won else -10.0) if q is None else 10*(a/up(q)-1)
    else:
        a=up(p); s=10/(a-1)
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
assert dn(2.0)==1.99 and up(2.0)==2.02 and up(1.99)==2.0 and dn(1.01)==1.01
assert abs(pnl('B',2.0,None,True)-9.702)<1e-9 and pnl('B',2.0,None,False)==-10.0 and pnl('B',1.02,None,True) is None     # 10*0.99*0.98; 1.02 -> 1.01 unfillable
assert abs(pnl('L',6.0,None,False)-10/5.2*0.98)<1e-9 and pnl('L',6.0,None,True)==-10.0                                     # lay fills 6.2, stake 10/5.2
assert abs(pnl('B',3.0,2.5,False)-1.788889)<1e-5                                                                           # 2.98/2.52: +1.825397, less 2%
assert abs(pnl('L',6.0,3.0,False)+2.077955)<1e-5                                                                           # 10/5.2*(1-6.2/2.98), a loss so no commission
assert result('BTTS','NO',0,0) and result('OU25','UNDER',1,1) and result('OU25','OVER',2,1) and result('MO','DRAW',0,0) and not result('BTTS','YES',2,0)  # line edges and 0-0
assert decided('OU15',1,1) and not decided('OU15',1,0) and decided('BTTS',1,1) and not decided('MO',5,0)
assert [state(*x) for x in ((0,0),(2,1),(1,2),(2,2),(3,0),(0,3),(3,1),(2,0))]==['0-0','2-1','1-2','2-2','3+','3+','3+','2-0']
assert [band(m) for m in (0,14,15,45,46,48,49,60,74,75,90,91)]==['00-15','00-15','15-30','30-45','HT','HT','45-60','45-60','60-75','75-90','75-90',None]
print("ladder + P&L + settlement + state unit checks: OK",flush=True)
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s';")
G=pd.read_sql("""SELECT m.event_id, f.fixture_id, f.season, f.league, f.hg, f.ag FROM af_price_map m
 JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL""",con)
print("games:",len(G),"| seasons:",G.season.value_counts().to_dict(),flush=True)
EV=pd.read_sql("""SELECT fixture_id, coalesce(minute,0) AS minute, is_home, type, detail FROM af_events WHERE fixture_id=ANY(%s)
 AND ((type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal')) OR (type='Card' AND detail='Red Card'))""",con,params=(list(map(int,G.fixture_id)),))
goals=defaultdict(list); reds=defaultdict(list)
for r in EV.itertuples():
    if r.type=='Goal': goals[r.fixture_id].append((int(r.minute),('h' if r.is_home else 'a') if r.detail!='Own Goal' else ('a' if r.is_home else 'h')))
    else: reds[r.fixture_id].append((int(r.minute),'h' if r.is_home else 'a'))
for d in (goals,reds):
    for k in d: d[k].sort()
SV=pd.read_sql("SELECT * FROM grid_survivors_v3",con); print("grid_survivors_v3 rows:",len(SV),"by exit:",SV.exit.value_counts().to_dict(),flush=True)
cells=defaultdict(lambda:[0,0.0,0.0,0,0.0,0,0.0,0.0]); SK=defaultdict(int)
v3c=defaultdict(lambda:[0,0.0,0.0]); v3l=defaultdict(lambda:[0,0.0,0.0])
align=defaultdict(lambda:[0,0.0]); t0=time.time(); ntr=0; ng=0
EX=('SETTLE','NEXTGOAL','P10','P20','T70','T80'); SEA={2024:1,2025:2}
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
        gl=goals.get(g.fixture_id,[]); hg,ag=int(g.hg),int(g.ag)
        if sum(1 for _,s in gl if s=='h')!=hg or sum(1 for _,s in gl if s=='a')!=ag: SK['af goal events disagree with FT score (game skipped)']+=1; continue
        s=SEA.get(int(g.season))
        if s is None: SK['season not 2024/2025']+=1; continue
        ng+=1
        H=b.get(('MO','HOME')); A=b.get(('MO','AWAY')); D=b.get(('MO','DRAW'))
        fb='n/a' if H is None or A is None or np.isnan(H[0]) or np.isnan(A[0]) else favband(min(H[0],A[0]))
        db='n/a' if D is None or np.isnan(D[0]) else drawband(D[0])
        gm=[m for m,_ in gl]
        # score known at a print at minute m = goals at minutes <= m-1
        hc=[sum(1 for x,y in gl if x<=m-1 and y=='h') for m in range(97)]; ac=[sum(1 for x,y in gl if x<=m-1 and y=='a') for m in range(97)]
        lg=[max([x for x in gm if x<=m-1],default=-9) for m in range(97)]
        # alignment study: MO home/away |log move| around each goal
        for gmin in gm:
            hf='1H' if gmin<=45 else '2H'
            for arr in (H,A):
                if arr is None: continue
                for off in range(-6,7):
                    a_,b_=gmin+off-1,gmin+off
                    if 0<=a_ and b_<=95 and not np.isnan(arr[a_]) and not np.isnan(arr[b_]):
                        c=align[(hf,off)]; c[0]+=1; c[1]+=abs(np.log(arr[b_]/arr[a_]))
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
                for ex in EX:
                    if ex=='SETTLE': tg=None
                    elif ex=='NEXTGOAL': tg=None if nxt is None or nxt+2>95 else nxt+2
                    elif ex=='P10': tg=m+10
                    elif ex=='P20': tg=m+20
                    else:
                        lim=70 if ex=='T70' else 80
                        if m>=lim: continue
                        tg=lim
                    q=None
                    if tg is not None:
                        e=nextp(max(tg,start+1))
                        if e is not None: q=float(arr[e])
                        else: SK[f'{ex} no print to 95 -> settled at result']+=1
                    for side,p in (('B',pb),('L',pl)):
                        if p>50: SK['entry price > 50 not traded']+=1; continue
                        r=pnl(side,float(p),q,won)
                        if r is None: SK['back at 1.01 unfillable']+=1; continue
                        c=cells[(st,bd,mkt,sel,side,ex,fb,db)]; c[0]+=1; c[1]+=r; c[2]+=r*r; c[7]+=p; ntr+=1
                        if s==1: c[3]+=1; c[4]+=r
                        else: c[5]+=1; c[6]+=r
        # job 323 NEXTGOAL re-derivation, V3 and HON
        if H is None or A is None or np.isnan(H[1]) or np.isnan(A[1]): continue
        fv=favband(min(H[1],A[1])); rl=reds.get(g.fixture_id,[]); season=int(g.season)
        for t in range(0,90,5):
            h=sum(1 for x,y in gl if x<=t and y=='h'); a=sum(1 for x,y in gl if x<=t and y=='a')
            diff=max(-2,min(2,h-a)); tot=min(3,h+a); red='none'
            for x,y in rl:
                if x<=t: red=y
            j=bisect.bisect_right(gm,t); nx=gm[j] if j<len(gm) else None
            tg=nx+2 if nx is not None and nx+2<=95 else None
            buffered=max([x for x in gm if x<=t],default=-9)>=t
            for (mkt,sel),arr in b.items():
                if sel not in MK.get(mkt,()): continue
                p0=arr[t+1]
                if np.isnan(p0) or p0>50 or decided(mkt,h,a): continue
                won=result(mkt,sel,hg,ag)
                later=np.flatnonzero(~np.isnan(arr[t+2:t+4])); n1=t+2+int(later[0]) if len(later) else None
                def xq(a0):
                    if tg is None: return None
                    w=np.flatnonzero(~np.isnan(arr[max(tg,a0):96]))
                    return float(arr[max(tg,a0)+int(w[0])]) if len(w) else None
                for side in ('B','L'):
                    r=pnl(side,float(p0),xq(t+1),won)
                    if r is not None:
                        for store,key in ((v3c,('V3',mkt,sel,side,t//10*10,diff,tot,red,fv,season)),(v3l,('V3',mkt,sel,side,t//15*15,diff,fv,g.league,season))):
                            c=store[key]; c[0]+=1; c[1]+=r; c[2]+=r*r
                    if buffered: continue
                    pw=float(p0) if n1 is None else float(min(p0,arr[n1]) if side=='B' else max(p0,arr[n1]))
                    if pw>50: continue
                    r=pnl(side,pw,xq((n1 if n1 is not None else t+1)+1),won)
                    if r is not None:
                        for store,key in ((v3c,('HON',mkt,sel,side,t//10*10,diff,tot,red,fv,season)),(v3l,('HON',mkt,sel,side,t//15*15,diff,fv,g.league,season))):
                            c=store[key]; c[0]+=1; c[1]+=r; c[2]+=r*r
    del px
    print(f"  {min(i+1000,len(G))}/{len(G)} games | priced {ng} | trades {ntr} | cells {len(cells)} | {int(time.time()-t0)}s",flush=True)
print("skips (counted):",dict(SK),flush=True)
print("\n== ALIGNMENT: mean |log move| in MO home/away, minute m-1 to m, by m minus af goal minute (the jump shows where the tape sees the goal)")
for hf in ('1H','2H'): print(hf,' '.join(f"{o:+d}:{align[(hf,o)][1]/max(align[(hf,o)][0],1):.3f}" for o in range(-6,7)),flush=True)
C=pd.DataFrame([k+tuple(v) for k,v in cells.items()],columns=['state','band','mkt','sel','side','exit','fav','draw','n','s','ss','n1','s1','n2','s2','sp'])
cur.execute("""DROP TABLE IF EXISTS grid_cells_v4; CREATE TABLE grid_cells_v4 (state TEXT, band TEXT, mkt TEXT, sel TEXT, side TEXT, exit TEXT, fav TEXT, draw TEXT,
  n INT, s DOUBLE PRECISION, ss DOUBLE PRECISION, n1 INT, s1 DOUBLE PRECISION, n2 INT, s2 DOUBLE PRECISION, sp DOUBLE PRECISION)""")
psycopg2.extras.execute_values(cur,"INSERT INTO grid_cells_v4 VALUES %s",C.itertuples(index=False,name=None),page_size=5000)
cur.execute("SELECT count(*) FROM grid_cells_v4"); print("grid_cells_v4 rows stored:",cur.fetchone()[0],"of",len(C),flush=True)
base=['state','band','mkt','sel','side','exit']; out=[]
for extra,lab in (([],'base'),(['fav'],'fav'),(['draw'],'draw'),(['fav','draw'],'fav+draw')):
    x=C.groupby(base+extra,as_index=False)[['n','s','ss','n1','s1','n2','s2','sp']].sum(); x['level']=lab
    for c in ('fav','draw'):
        if c not in x: x[c]='*'
    out.append(x)
R=pd.concat(out,ignore_index=True); R['per10']=R.s/R.n; R['sd']=np.sqrt(np.maximum(R.ss/R.n-R.per10**2,1e-9)); R['t']=R.per10/(R.sd/np.sqrt(R.n))
R['h1']=R.s1/R.n1.replace(0,np.nan); R['h2']=R.s2/R.n2.replace(0,np.nan); R['px']=R.sp/R.n
R['PASS']=(R.n>=300)&(R.n1>=150)&(R.n2>=150)&(R.t>=3.5)&(R.h1>0)&(R.h2>0)&(R.per10>=0.15)
T=R[R.n>=300]; bonf=NormalDist().inv_cdf(1-0.05/2/max(len(T),1))
pd.set_option('display.width',260); pd.set_option('display.max_rows',200); pd.set_option('display.max_columns',40)
cols=['level','state','band','mkt','sel','side','exit','fav','draw','n','px','per10','t','n1','h1','n2','h2','PASS']
print(f"\n==== GRID v4: {len(R)} cells, {len(T)} with n>=300; Bonferroni t at 5% across those = {bonf:.2f}; games priced {ng}, trades {ntr} ====")
print("\n== top 20 by t (n>=300), whatever they are"); print(T.sort_values('t',ascending=False).head(20)[cols].round(3).to_string(index=False))
print("\n== top 15 by t, base level only"); print(T[T.level=='base'].sort_values('t',ascending=False).head(15)[cols].round(3).to_string(index=False))
print("\n== cells at n>=300 by exit: count, share positive, best t"); print(T.groupby('exit').agg(cells=('t','size'),pos=('per10',lambda v:(v>0).mean()),best_t=('t','max')).round(3).to_string())
# ---- v3 NEXTGOAL re-derivation
def frame(store,names): return pd.DataFrame([k+tuple(v) for k,v in store.items()],columns=names+['n','s','ss'])
F=frame(v3c,['var','mkt','sel','side','tband','diff','tot','red','fav','season']); L=frame(v3l,['var','mkt','sel','side','tband','diff','fav','league','season'])
NG=SV[SV.exit=='NEXTGOAL'].copy(); rows=[]
def stat(x):
    if x.empty: return dict(n=0,mean=np.nan,t=np.nan,h1=np.nan,h2=np.nan,n1=0,n2=0)
    n=x.n.sum(); s=x.s.sum(); ss=x.ss.sum(); m=s/n; sd=max(ss/n-m*m,1e-9)**0.5
    a=x[x.season==2024]; b=x[x.season==2025]
    return dict(n=int(n),mean=m,t=m/(sd/n**0.5),h1=a.s.sum()/a.n.sum() if a.n.sum() else np.nan,h2=b.s.sum()/b.n.sum() if b.n.sum() else np.nan,n1=int(a.n.sum()),n2=int(b.n.sum()))
Fg={k:v for k,v in F.groupby(['var','mkt','sel','side','tband'])}; Lg={k:v for k,v in L.groupby(['var','mkt','sel','side','tband'])}
for r in NG.itertuples():
    rec=dict(level=r.level,mkt=r.mkt,sel=r.sel,side=r.side,tband=r.tband,diff=r.diff,tot=r.tot,red=r.red,fav=r.fav,league=r.league,n_v3=r.n,mean_v3=float(r.mean),t_v3=float(r.t))
    for var in ('V3','HON'):
        x=(Lg if pd.notna(r.league) else Fg).get((var,r.mkt,r.sel,r.side,r.tband),pd.DataFrame())
        if not x.empty:
            for col,val in (('diff',r.diff),('tot',r.tot),('red',r.red),('fav',r.fav),('league',r.league)):
                if pd.notna(val) and col in x: x=x[x[col]==val]
        st_=stat(x)
        for k,v in st_.items(): rec[f'{k}_{var}']=v
        rec[f'pass_{var}']=st_['n']>=300 and st_['n1']>=150 and st_['n2']>=150 and st_['t']>=3.5 and st_['h1']>0 and st_['h2']>0 and st_['mean']>=0.15
    rows.append(rec)
Q=pd.DataFrame(rows)
if len(Q):
    print(f"\n== V3 RE-DERIVATION: {len(Q)} NEXTGOAL survivors. Replica reproduces v3 mean within £0.05 on {(abs(Q.mean_V3-Q.mean_v3)<=0.05).sum()}; pass at standard filter, V3 replica {Q.pass_V3.sum()}, HON {Q.pass_HON.sum()}")
    print(f"mean of per-£10 across the {len(Q)}: stored {Q.mean_v3.mean():.3f}, replica {Q.mean_V3.mean():.3f}, HON {Q.mean_HON.mean():.3f}")
    print(Q.sort_values('t_v3',ascending=False).head(15)[['level','mkt','sel','side','tband','diff','n_v3','mean_v3','t_v3','n_V3','mean_V3','t_V3','n_HON','mean_HON','t_HON','h1_HON','h2_HON','pass_HON']].round(3).to_string(index=False))
    H_=Q[Q.pass_HON].sort_values('t_HON',ascending=False)
    print(f"\n== v3 NEXTGOAL lines still passing on HON: {len(H_)}"); print(H_.head(25)[['level','mkt','sel','side','tband','diff','tot','red','fav','league','n_HON','mean_HON','t_HON','h1_HON','h2_HON']].round(3).to_string(index=False) if len(H_) else "none")
S=R[R.PASS].sort_values('t',ascending=False)
print(f"\n== SURVIVORS: {len(S)} (of {len(T)} cells at n>=300), of which at or above the Bonferroni t: {(S.t>=bonf).sum()}"); print(S.head(60)[cols].round(3).to_string(index=False) if len(S) else "none")
PY
