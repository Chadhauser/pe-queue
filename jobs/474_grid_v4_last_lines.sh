#!/bin/bash
set -o pipefail
# 474 (Finder 2026-11-03, queue item 19, closing the last open lines of 471/473).
# PART A: reconcile 473 part A (n 778, +0.724) with 471 (n 770, +0.570) for the same rule, BTTS YES lay, 0-0, first print at 75-90, settle: rebuild both trade lists from one pull and print the games that differ.
# PART B: the v3 lines still passing at g+8 in 471 have up to 3 entries per game (t 30,35,40 in one band), which inflates t. Re-test at ONE entry per game: first t in the band with the state true, print at t+1, fill = worse of that and the
#   next real print within 2 min, last known goal at least 2 min old, exit first real print at/after next goal +8 else settle at the result, £10 risk, 2% commission, season halves. Every league is shown, so La Liga can be ranked against a placebo of the other 28.
#   x3 = 3 further adverse ticks at entry. Own goals are NOT flipped (see 471).
# PART C: reads the 2-2 late draw near-miss out of grid_cells_v4 (built by 471).
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,psycopg2,pandas as pd,numpy as np
from collections import defaultdict
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
LAD=[]
for lo,hi,st in ((1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)):
    x=lo
    while x<hi-1e-9: LAD.append(round(x,2)); x+=st
LAD.append(1000.0); LADA=np.array(LAD)
def ti(p): return int(np.searchsorted(LADA,round(p,2)-1e-9))
def dn(p,k=1): return float(LADA[max(ti(p)-k,0)])
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
LINE={'OU15':1.5,'OU25':2.5}
def result(mkt,sel,hg,ag):
    if mkt=='MO': return hg==ag if sel=='DRAW' else (hg>ag if sel=='HOME' else hg<ag)
    return (hg+ag>LINE[mkt])==(sel=='OVER')
def tstat(x):
    x=np.asarray(x,dtype=float); s=x.std(ddof=1) if len(x)>1 else 0
    return x.mean()/(s/len(x)**0.5) if s>0 else 0.0
# known answers, worked by hand: back 2.0 -> 1.99 wins 10*0.99*0.98 = 9.702; lay 6.0 -> 6.2 keeps 10/5.2*0.98 = 1.884615; 3 extra-adverse fill back 2.0 -> 1.97; 2-1 is OVER 2.5, 1-1 is not; 1-1 is OVER 1.5
assert abs(pnl('B',2.0,None,True)-9.702)<1e-9 and abs(pnl('L',6.0,None,False)-1.884615)<1e-5 and dn(2.0,3)==1.97
assert result('OU25','OVER',2,1) and not result('OU25','OVER',1,1) and result('OU15','OVER',1,1) and result('MO','DRAW',0,0)
print("unit checks: OK",flush=True)
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s';")
G=pd.read_sql("""SELECT m.event_id, f.fixture_id, f.season, f.league, f.hg, f.ag, f.ht_hg, f.ht_ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL""",con)
EV=pd.read_sql("SELECT fixture_id, coalesce(minute,0) AS minute, is_home FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal')",con,params=(list(map(int,G.fixture_id)),))
goals=defaultdict(list)
for r in EV.itertuples(): goals[r.fixture_id].append((int(r.minute),'h' if r.is_home else 'a'))
for k in goals: goals[k].sort()
# ---- PART A
A471=[]; A473=[]
LINES=[('MO','DRAW','L',30,0,None,None),('OU15','UNDER','L',30,0,None,None),('OU15','OVER','B',30,0,None,None),('OU25','OVER','B',30,0,None,None),('OU25','UNDER','B',60,1,'1.5-2',None)]
B=[]
def favband(f): return '<1.5' if f<1.5 else '1.5-2' if f<2 else '2-3' if f<3 else '3+'
for i in range(0,len(G),1000):
    sub=G.iloc[i:i+1000]
    P=pd.read_sql("SELECT event_id, minute, mkt, sel, ltp::float ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt IN ('MO','OU15','OU25','BTTS') AND minute BETWEEN 0 AND 95 AND ltp>=1.01 AND ltp<1000",con,params=(list(sub.event_id),))
    px={}
    for (eid,mkt,sel),gg in P.groupby(['event_id','mkt','sel'],sort=False):
        arr=np.full(97,np.nan); arr[gg.minute.values]=gg.ltp.values; px.setdefault(eid,{})[(mkt,sel)]=arr
    del P
    for g in sub.itertuples():
        b=px.get(g.event_id)
        if not b: continue
        gl=goals.get(g.fixture_id,[]); gm=[m for m,_ in gl]; hg,ag=int(g.hg),int(g.ag); s=int(g.season)
        arr=b.get(('BTTS','YES'))
        if arr is not None:
            bw=hg>0 and ag>0; f=gm[0] if gm else 999
            idx=np.flatnonzero(~np.isnan(arr)).tolist()
            for j,m in enumerate(idx):
                if 75<=m<=90 and f>=m:
                    nxt=arr[idx[j+1]] if j+1<len(idx) and idx[j+1]<=m+2 else arr[m]
                    p=max(arr[m],nxt)
                    # 471's rule: first print in the band with 0-0 known; skipped if the worse-of fill is above 50
                    if p<=50: A471.append(dict(ev=g.event_id,m=m,ltp=arr[m],p=p,won=bw,r=pnl('L',float(p),None,bw)))
                    # 473's rule: stops only if the print itself is above 50; and only games at 0-0 at HT by af_fixtures
                    if arr[m]<=50 and g.ht_hg==0 and g.ag==g.ag and g.ht_ag==0: A473.append(dict(ev=g.event_id,m=m,ltp=arr[m],p=p,won=bw,r=pnl('L',float(p),None,bw)))
                    break
        H=b.get(('MO','HOME')); A=b.get(('MO','AWAY'))
        fv=favband(min(H[1],A[1])) if H is not None and A is not None and not np.isnan(H[1]) and not np.isnan(A[1]) else 'n/a'
        for mkt,sel,side,tb,dfv,fb,_ in LINES:
            arr=b.get((mkt,sel))
            if arr is None or (fb and fv!=fb): continue
            won=result(mkt,sel,hg,ag)
            for t in range(tb,tb+15,5):
                if np.isnan(arr[t+1]): continue
                h=sum(1 for x,y in gl if x<=t and y=='h'); a=sum(1 for x,y in gl if x<=t and y=='a')
                if max(-2,min(2,h-a))!=dfv or max([x for x in gm if x<=t],default=-9)>=t: continue
                if mkt in LINE and h+a>LINE[mkt]: continue
                later=np.flatnonzero(~np.isnan(arr[t+2:t+4])); n1=t+2+int(later[0]) if len(later) else None
                p0=float(arr[t+1]); pw=p0 if n1 is None else float(min(p0,arr[n1]) if side=='B' else max(p0,arr[n1]))
                if pw>50: break
                st=(n1 if n1 is not None else t+1)+1
                nx=next((x for x in gm if x>t),None); q=None
                if nx is not None and nx+8<=95:
                    tg=max(nx+8,st); w=np.flatnonzero(~np.isnan(arr[tg:96]))
                    if len(w): q=float(arr[tg+int(w[0])])
                r1=pnl(side,pw,q,won); r3=pnl(side,pw,q,won,4)
                if r1 is not None and r3 is not None: B.append(dict(line=f"{mkt} {sel} {side} t{tb} d{dfv}"+(f" fav{fb}" if fb else ''),league=g.league,season=s,r=r1,r3=r3,ev=g.event_id))
                break
    del px
X=pd.DataFrame(A471); Y=pd.DataFrame(A473); pd.set_option('display.width',220); pd.set_option('display.max_rows',80)
print(f"\n== PART A: 471 rule n {len(X)}, {X.r.mean():+.3f}, YES won {int(X.won.sum())} | 473 rule n {len(Y)}, {Y.r.mean():+.3f}, YES won {int(Y.won.sum())}")
Z=X.merge(Y,on='ev',how='outer',suffixes=('_471','_473'),indicator=True)
print("only in 471:",int((Z._merge=='left_only').sum()),"sum £",round(Z[Z._merge=='left_only'].r_471.sum(),2),"| only in 473:",int((Z._merge=='right_only').sum()),"sum £",round(Z[Z._merge=='right_only'].r_473.sum(),2),"| same game, different P&L:",int(((Z._merge=='both')&(abs(Z.r_471-Z.r_473)>1e-9)).sum()))
print(Z[Z._merge!='both'].assign(r=lambda d:d.r_471.fillna(d.r_473)).sort_values('r',key=abs,ascending=False).head(8)[['_merge','m_471','m_473','ltp_471','ltp_473','p_471','p_473','r']].round(3).to_string(index=False))
R=pd.DataFrame(B)
print("\n== PART B: one entry per game, exit g+8. Line total, then La Liga, its rank among leagues with n>=100, and how many of those leagues are t>=3.5")
for ln,x in R.groupby('line'):
    a=x[x.season==2024]; b=x[x.season==2025]
    print(f"\n{ln}: ALL leagues n {len(x)} {x.r.mean():+.3f} t {tstat(x.r):.2f} h1 {a.r.mean():+.3f} h2 {b.r.mean():+.3f} | x3 ticks {x.r3.mean():+.3f} t {tstat(x.r3):.2f}")
    T=[]
    for lg,y in x.groupby('league'):
        a=y[y.season==2024]; b=y[y.season==2025]
        T.append(dict(league=lg,n=len(y),per10=y.r.mean(),t=tstat(y.r),n1=len(a),h1=a.r.mean() if len(a) else np.nan,n2=len(b),h2=b.r.mean() if len(b) else np.nan,x3=y.r3.mean(),t_x3=tstat(y.r3)))
    T=pd.DataFrame(T); T100=T[T.n>=100].sort_values('t',ascending=False).reset_index(drop=True); T100['PASS']=(T100.n>=300)&(T100.n1>=150)&(T100.n2>=150)&(T100.t>=3.5)&(T100.h1>0)&(T100.h2>0)&(T100.per10>=0.15)
    print(f"leagues n>=100: {len(T100)}, t>=3.5: {(T100.t>=3.5).sum()}, full PASS: {T100.PASS.sum()}"); print(T100.head(4).round(3).to_string(index=False))
    ll=T100[T100.league=='La Liga']
    if len(ll): print("La Liga rank",int(ll.index[0])+1,"of",len(T100))
# ---- PART C
Q=pd.read_sql("""SELECT exit, sum(n) n, sum(s)/sum(n) per10, sum(s1)/nullif(sum(n1),0) h1, sum(s2)/nullif(sum(n2),0) h2, sum(n1) n1, sum(n2) n2, sum(ss) ss, sum(s) s, sum(sp)/sum(n) px FROM grid_cells_v4
  WHERE state='2-2' AND mkt='MO' AND sel='DRAW' AND side='B' AND band IN ('60-75','75-90') AND exit IN ('SETTLE','SETTLEx3','SETTLEx5','NG8','NG10') GROUP BY exit ORDER BY exit""",con)
Q['t']=Q.per10/np.sqrt((Q.ss/Q.n-Q.per10**2)/Q.n)
print("\n== PART C: back the draw at 2-2, 60-90 pooled (a game can be in both bands)"); print(Q[['exit','n','n1','n2','px','per10','t','h1','h2']].round(3).to_string(index=False))
Q2=pd.read_sql("""SELECT band, exit, sum(n) n, sum(s)/sum(n) per10, sum(s1)/nullif(sum(n1),0) h1, sum(s2)/nullif(sum(n2),0) h2, sum(ss) ss, sum(s) s FROM grid_cells_v4
  WHERE state='2-2' AND mkt='MO' AND sel='DRAW' AND side='B' AND band IN ('60-75','75-90') AND exit IN ('SETTLE','SETTLEx3','NG8') GROUP BY 1,2 ORDER BY 1,2""",con)
Q2['t']=Q2.per10/np.sqrt((Q2.ss/Q2.n-Q2.per10**2)/Q2.n); print(Q2[['band','exit','n','per10','t','h1','h2']].round(3).to_string(index=False))
print("\n== SURVIVORS: judged in the report from PART B (full PASS at one entry per game)")
PY
