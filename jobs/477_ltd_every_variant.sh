#!/bin/bash
set -o pipefail
# 477 (Finder 2026-11-03, queue item 22): LAY THE DRAW, EVERY VARIANT. bf_hist_price MO DRAW x af_fixtures/af_events, two seasons (12,255 mapped games; league dimension included).
# ENTRY E = 0', 10', 20', 30': first real print at minutes E..E+4 with no goal known (no goal at minutes <= print - 1). A goal AT the print minute is kept (dropping it is look-ahead). Fill = worse (higher) of that print and the next real print within 2 min, one tick adverse.
#   Price > 50 not traded. One entry per game per E. £10 liability, 2% commission, halves = season 2024 v 2025. Tape "minute 0" is a median 2 min after kick-off (jobs/472_prematch_band_sweep), so E=0 is not a pre-match fill.
# EXITS: first real print at/after the target, after the fill; none to 95' = settled at the RESULT, never dropped.
#   NG2 / NG8 = first goal (any side) +2 / +8, no goal = settle. FAV2 / FAV8 = first goal BY THE FAVOURITE +2 / +8 (kick-off shorter of home/away), no such goal = settle. T60, T70 (entries before that minute). SETTLE. SETTLEx3 = settle with 3 extra adverse ticks (real draw lay gap at 3-5: median 2, p90 12).
# +2 EXITS CANNOT PASS: jobs/471 showed af goal minutes and the tape clock disagree, so g+2 often sells before the goal is in the price. For a LAY of the draw that clock error works AGAINST the trade, so they are shown for comparison only.
# BANDS: draw at the entry print (<2.5, 2.5-3, 3-3.6, 3.6-4.5, 4.5-5.5, 5.5+); favourite at the minute-0 print (<=1.5, 1.5-2, 2-3, 3+); league.
# S1 rule exactly: away favourite 1.60-2.20 and draw 4.00-4.50 at the minute-0 prints, E=0, shown on every exit (vendor claim +10.7% ROI, item 30). Own goals NOT flipped (jobs/471).
# NOT TESTED: S1-AUTO overnight rules and the known-avoid list: neither is defined anywhere in this repo.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,time,bisect,psycopg2,pandas as pd,numpy as np
from collections import defaultdict
from statistics import NormalDist
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
LAD=[]
for lo,hi,st in ((1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)):
    x=lo
    while x<hi-1e-9: LAD.append(round(x,2)); x+=st
LAD.append(1000.0); LADA=np.array(LAD)
def ti(p): return int(np.searchsorted(LADA,round(p,2)-1e-9))
def dn(p,k=1): return float(LADA[max(ti(p)-k,0)])
def up(p,k=1): return float(LADA[min(ti(p)+k,len(LADA)-1)])
def lay(p,q,won,k=1):
    a=up(p,k); s=10/(a-1)
    r=(s if not won else -10.0) if q is None else s*(1-a/dn(q))
    return r*0.98 if r>0 else r
def first_goal(gl,m,side=None):
    for x,y in gl:
        if x>=m and (side is None or y==side): return x
    return None
def dband(d): return '<2.5' if d<2.5 else '2.5-3' if d<3 else '3-3.6' if d<3.6 else '3.6-4.5' if d<4.5 else '4.5-5.5' if d<5.5 else '5.5+'
def fband(f): return '<=1.5' if f<=1.5 else '1.5-2' if f<=2 else '2-3' if f<=3 else '3+'
# known answers, worked by hand:
assert abs(lay(4.0,None,False)-3.161290)<1e-5 and lay(4.0,None,True)==-10.0     # 4.0 fills 4.1, stake 10/3.1 = 3.225806, keep 3.161290 after 2%; draw wins: lose £10
assert abs(lay(4.0,8.0,False)-1.499586)<1e-5                                    # draw drifts to 8.0, back out at 7.8: 3.225806 x (1-4.1/7.8) = 1.530190, less 2%
assert abs(lay(4.0,3.0,False)+1.212385)<1e-5                                   # draw shortens to 3.0, back out at 2.98: 3.225806 x (1-4.1/2.98), a loss so no commission
assert abs(lay(4.0,None,False,4)-10/3.4*0.98)<1e-9                              # x3 = 4 ticks up from 4.0 = 4.4, stake 10/3.4
GL=[(20,'a'),(55,'h')]
assert first_goal(GL,0)==20 and first_goal(GL,0,'h')==55 and first_goal(GL,21)==55 and first_goal(GL,56) is None and first_goal(GL,20)==20 and first_goal([],0) is None
assert [dband(x) for x in (2.49,2.5,3.0,3.6,4.5,5.5)]==['<2.5','2.5-3','3-3.6','3.6-4.5','4.5-5.5','5.5+'] and [fband(x) for x in (1.5,1.51,2.0,3.0,3.01)]==['<=1.5','1.5-2','1.5-2','2-3','3+']
print("P&L + goal + band unit checks: OK",flush=True)
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s';")
G=pd.read_sql("""SELECT m.event_id, f.fixture_id, f.season, f.league, f.hg, f.ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL""",con)
EV=pd.read_sql("SELECT fixture_id, coalesce(minute,0) AS minute, is_home FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal')",con,params=(list(map(int,G.fixture_id)),))
goals=defaultdict(list)
for r in EV.itertuples(): goals[r.fixture_id].append((int(r.minute),'h' if r.is_home else 'a'))
for k in goals: goals[k].sort()
print("games",len(G),"seasons",G.season.value_counts().to_dict(),flush=True)
cells=defaultdict(lambda:[0,0.0,0.0,0,0.0,0,0.0,0.0]); SK=defaultdict(int); t0=time.time(); ntr=0
EXITS=('NG2','NG8','FAV2','FAV8','T60','T70','SETTLE','SETTLEx3')
for i in range(0,len(G),1500):
    sub=G.iloc[i:i+1500]
    P=pd.read_sql("SELECT event_id, minute, sel, ltp::float ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt='MO' AND minute BETWEEN 0 AND 95 AND ltp>=1.01 AND ltp<1000",con,params=(list(sub.event_id),))
    px={}
    for (eid,sel),gg in P.groupby(['event_id','sel'],sort=False):
        arr=np.full(97,np.nan); arr[gg.minute.values]=gg.ltp.values; px.setdefault(eid,{})[sel]=arr
    del P
    for g in sub.itertuples():
        b=px.get(g.event_id)
        if not b or 'DRAW' not in b: SK['no draw prices']+=1; continue
        D=b['DRAW']; H=b.get('HOME'); A=b.get('AWAY'); gl=goals.get(g.fixture_id,[]); won=int(g.hg)==int(g.ag); s=int(g.season)
        ok0=H is not None and A is not None and not np.isnan(H[0]) and not np.isnan(A[0])
        fb=fband(min(H[0],A[0])) if ok0 else 'n/a'; fav=('h' if H[0]<=A[0] else 'a') if ok0 else None
        s1=bool(ok0 and A[0]<H[0] and 1.60<=A[0]<=2.20 and not np.isnan(D[0]) and 4.0<=D[0]<=4.5)
        idx=np.flatnonzero(~np.isnan(D)).tolist(); fg=gl[0][0] if gl else 999
        def nextp(a,b_=95):
            j=bisect.bisect_left(idx,a)
            return idx[j] if j<len(idx) and idx[j]<=b_ else None
        for E in (0,10,20,30):
            m=nextp(E,E+4)
            if m is None: SK[f'E{E} no print']+=1; continue
            if fg<=m-1: SK[f'E{E} goal already scored']+=1; continue
            n1=nextp(m+1,m+2); p=float(D[m]) if n1 is None else float(max(D[m],D[n1]))
            if p>50: SK['price > 50']+=1; continue
            start=n1 if n1 is not None else m
            db=dband(p)
            for ex in EXITS:
                tg=None
                if ex in ('NG2','NG8'):
                    x=first_goal(gl,m); tg=None if x is None else x+int(ex[2])
                elif ex in ('FAV2','FAV8'):
                    if fav is None: continue
                    x=first_goal(gl,m,fav); tg=None if x is None else x+int(ex[3])
                elif ex in ('T60','T70'):
                    tg=int(ex[1:])
                q=None
                if tg is not None and tg<=95:
                    e=nextp(max(tg,start+1))
                    if e is not None: q=float(D[e])
                r=lay(p,q,won,4 if ex=='SETTLEx3' else 1)
                c=cells[(E,ex,db,fb,g.league,s1 and E==0)]; c[0]+=1; c[1]+=r; c[2]+=r*r; c[7]+=p; ntr+=1
                if s==2024: c[3]+=1; c[4]+=r
                else: c[5]+=1; c[6]+=r
    del px
    print(f"  {min(i+1500,len(G))}/{len(G)} games | trades {ntr} | cells {len(cells)} | {int(time.time()-t0)}s",flush=True)
print("skips (counted):",dict(SK),flush=True)
C=pd.DataFrame([k+tuple(v) for k,v in cells.items()],columns=['E','exit','draw','fav','league','s1','n','s','ss','n1','s1_','n2','s2','sp'])
vals=['n','s','ss','n1','s1_','n2','s2','sp']; out=[]
for extra,lab in (([],'base'),(['draw'],'draw'),(['fav'],'fav'),(['league'],'league'),(['draw','fav'],'draw+fav'),(['draw','league'],'draw+league'),(['fav','league'],'fav+league')):
    x=C.groupby(['E','exit']+extra,as_index=False)[vals].sum(); x['level']=lab
    for c in ('draw','fav','league'):
        if c not in x: x[c]='*'
    out.append(x)
R=pd.concat(out,ignore_index=True)
def fin(R):
    R=R.copy(); R['per10']=R.s/R.n; R['sd']=np.sqrt(np.maximum(R.ss/R.n-R.per10**2,1e-9)); R['t']=R.per10/(R.sd/np.sqrt(R.n))
    R['h1']=R.s1_/R.n1.replace(0,np.nan); R['h2']=R.s2/R.n2.replace(0,np.nan); R['px']=R.sp/R.n
    R['PASS']=(R.n>=300)&(R.n1>=150)&(R.n2>=150)&(R.t>=3.5)&(R.h1>0)&(R.h2>0)&(R.per10>=0.15)&(~R.exit.isin(['NG2','FAV2']))
    return R
R=fin(R); T=R[R.n>=300]; bonf=NormalDist().inv_cdf(1-0.05/2/max(len(T),1))
pd.set_option('display.width',240); pd.set_option('display.max_rows',200); pd.set_option('display.max_columns',30)
cols=['level','E','exit','draw','fav','league','n','px','per10','t','n1','h1','n2','h2','PASS']
print(f"\n==== LTD: {len(R)} cells, {len(T)} at n>=300; Bonferroni t {bonf:.2f}; trades {ntr} ====")
print("\n== base: every entry x exit"); print(R[R.level=='base'].sort_values(['E','exit'])[['E','exit','n','px','per10','t','h1','h2']].round(3).to_string(index=False))
print("\n== by draw band, E=0, settle and NG8"); print(R[(R.level=='draw')&(R.E==0)&(R.exit.isin(['SETTLE','NG8']))].sort_values(['exit','draw'])[['exit','draw','n','px','per10','t','h1','h2']].round(3).to_string(index=False))
S1=fin(C[C.s1].groupby('exit',as_index=False)[vals].sum())
print("\n== S1 rule exactly: away favourite 1.60-2.20, draw 4.00-4.50 at minute 0, E=0 (vendor claim +10.7% ROI; £10 liability at about 4.3 is a stake of about £3, so per £10 here is not ROI: roi = per10 / mean stake)")
S1['stake']=10/(S1.px.map(up)-1); S1['roi_pct']=100*S1.per10/S1.stake
print(S1[['exit','n','px','per10','t','n1','h1','n2','h2','stake','roi_pct','PASS']].round(3).to_string(index=False))
print("\n== top 20 by t, n>=300, exits +8 / times / settle"); print(T[~T.exit.isin(['NG2','FAV2'])].sort_values('t',ascending=False).head(20)[cols].round(3).to_string(index=False))
print("\n== top 8 by t, n>=300, +2 exits, comparison only"); print(T[T.exit.isin(['NG2','FAV2'])].sort_values('t',ascending=False).head(8)[cols].round(3).to_string(index=False))
print("\n== passes by exit"); print(R.groupby('exit').agg(cells=('n',lambda v:(v>=300).sum()),passes=('PASS','sum')).to_string())
W=R[R.PASS].sort_values('t',ascending=False)
print(f"\n== SURVIVORS: {len(W)} (of {len(T)} cells at n>=300), at or above the Bonferroni t: {(W.t>=bonf).sum()}"); print(W.head(40)[cols].round(3).to_string(index=False) if len(W) else "none")
PY
