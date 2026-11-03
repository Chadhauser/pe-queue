#!/bin/bash
set -o pipefail
# 476 (Finder 2026-11-03, queue item 21): HT FAMILY WITH THE FAVOURITE. Every HT score x OU15/OU25/OU35 OVER/UNDER x back/lay x pre-match favourite status (HF home <=1.8, AF away <=1.8, NF neither, NA no print)
# x league, at the first real print after 46'. HT score from af_fixtures; favourite from the earliest MO print in tape minutes 0..2 (the tape has no pre-kick-off rows, job 472).
# ENTRY: decision at the first real print at minutes 46-48; FILL at the worse of that print and the next real print within 2 minutes; one tick adverse on the exact ladder. Price > 50 not traded.
#   A selection already decided at HT is not traded. A 2H goal strictly BEFORE the decision minute skips the selection (counted). A goal in the same minute stays: dropping it is look-ahead.
# EXITS: SETTLE; T70 first real print at/after 70'; NG2 and NG5 first real print at/after next goal +2 / +5. No print to 95' = settled at the RESULT, never dropped. No next goal = settled at the result.
#   NG5 is there because job 471 showed a goal-minute exit can leak if the tape clock runs behind af: a real NG2 edge must survive at NG5. A NG2 cell only passes if its NG5 twin also passes.
# COST: £10 risk, 2% commission on profit. t3 = two further adverse ticks at entry, because LTP is not the touch (job 471: thin-market gaps are large).
# GUARD: game dropped, blind to the result, when its first MO print is more than 5 min before or 20 min after the af kick-off (job 472: bad mapping or rescheduled). Halves: season 2024 v 2025.
# One entry per game per selection per exit per side, so games in a cell are independent; cells overlap. Bonferroni t printed.
# Writes ht_family_v1 in one transaction: runner/runner.sh also runs any new job file, and overlapping non-transactional runs double the rows (found on job 472).
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,time,warnings,psycopg2,psycopg2.extras,pandas as pd,numpy as np
from collections import defaultdict
from functools import lru_cache
from statistics import NormalDist
warnings.filterwarnings('ignore')
pd.set_option('display.width',240); pd.set_option('display.max_rows',200); pd.set_option('display.max_columns',40)
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
LAD=[]
for lo,hi,st in ((1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)):
    x=lo
    while x<hi-1e-9: LAD.append(round(x,2)); x+=st
LAD.append(1000.0); LADA=np.array(LAD)
@lru_cache(maxsize=None)
def dn(p,k=1): return float(LADA[max(int(np.searchsorted(LADA,round(p,2)-1e-9))-k,0)])
@lru_cache(maxsize=None)
def up(p,k=1): return float(LADA[min(int(np.searchsorted(LADA,round(p,2)-1e-9))+k,len(LADA)-1)])
def pnl(side,p,q,won,k=1):
    if side=='B':
        a=dn(p,k)
        if a<=1.01: return None
        r=(10*(a-1) if won else -10.0) if q is None else 10*(a/up(q)-1)
    else:
        a=up(p,k); s=10/(a-1)
        r=(s if not won else -10.0) if q is None else s*(1-a/dn(q))
    return r*0.98 if r>0 else r
LINE={'OU15':1.5,'OU25':2.5,'OU35':3.5}
def result(mkt,sel,hg,ag): return (hg+ag>LINE[mkt])==(sel=='OVER')
def decided(mkt,h,a): return h+a>LINE[mkt]
def st(h,a): return '3+' if h+a>=3 else f"{h}-{a}"
def favst(h,a):
    if h is None or a is None: return 'NA'
    return 'HF' if h<=1.8 and h<=a else 'AF' if a<=1.8 else 'NF'
def rp(arr,a,b):
    for mm in range(max(0,a),min(b,95)+1):
        if not np.isnan(arr[mm]): return mm
    return None
def fill(arr,d,side):
    n=rp(arr,d+1,d+2)
    return arr[d] if n is None else (min(arr[d],arr[n]) if side=='B' else max(arr[d],arr[n]))
def nxt_goal(g2,d):
    return next((m for m in g2 if m>=d),None)
def exit_px(arr,start):
    e=rp(arr,start,95)
    return None if e is None else arr[e]
# known answers, worked by hand
assert dn(2.0)==1.99 and up(2.0)==2.02 and up(1.99)==2.0 and dn(1.01)==1.01 and up(2.0,3)==2.06
assert abs(pnl('B',2.0,None,True)-9.702)<1e-9 and pnl('B',2.0,None,False)==-10.0 and pnl('B',1.02,None,True) is None
assert abs(pnl('L',6.0,None,False)-10/5.2*0.98)<1e-9 and pnl('L',6.0,None,True)==-10.0
assert abs(pnl('B',3.0,2.5,False)-1.788889)<1e-5      # 2.98/2.52 = +1.825397, less 2%
assert abs(pnl('L',6.0,3.0,False)+2.077955)<1e-5      # 10/5.2*(1-6.2/2.98), a loss so no commission
assert abs(pnl('B',2.0,None,True,3)-10*0.97*0.98)<1e-9
assert result('OU25','OVER',2,1) and result('OU25','UNDER',1,1) and not result('OU35','OVER',2,1) and result('OU15','UNDER',0,1) and result('OU15','UNDER',0,0)
assert decided('OU15',1,1) and not decided('OU15',1,0) and decided('OU25',2,1) and not decided('OU35',2,1)
assert st(0,0)=='0-0' and st(1,2)=='3+' and st(2,0)=='2-0' and st(0,2)=='0-2' and st(1,1)=='1-1'
assert favst(1.8,3.0)=='HF' and favst(1.81,3.0)=='NF' and favst(4.0,1.8)=='AF' and favst(None,1.5)=='NA' and favst(1.5,1.6)=='HF' and favst(1.7,1.5)=='AF'
_a=np.full(96,np.nan); _a[46]=2.0; _a[47]=1.9; _a[60]=3.0
assert rp(_a,46,48)==46 and rp(_a,48,59) is None and fill(_a,46,'B')==1.9 and fill(_a,46,'L')==2.0 and exit_px(_a,61) is None and exit_px(_a,50)==3.0
assert nxt_goal([50,60],50)==50 and nxt_goal([50,60],51)==60 and nxt_goal([50],51) is None
print("known-answer checks: OK",flush=True)

con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
G=pd.read_sql("""SELECT m.event_id,f.fixture_id,f.season,f.league_id,f.league,f.kickoff,f.hg,f.ag,f.ht_hg,f.ht_ag FROM af_price_map m
 JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL AND f.ht_hg IS NOT NULL""",con)
G['state']=[st(int(h),int(a)) for h,a in zip(G.ht_hg,G.ht_ag)]
print("games:",len(G),"| HT states:",G.state.value_counts().to_dict(),flush=True)
EV=pd.read_sql("""SELECT fixture_id,coalesce(minute,0) AS minute FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal') AND coalesce(minute,0)>45""",con,params=(list(map(int,G.fixture_id)),))
g2=defaultdict(list)
for r in EV.itertuples(): g2[r.fixture_id].append(int(r.minute))
for k in g2: g2[k].sort()
OU=('OVER','UNDER'); EXITS=('SETTLE','T70','NG2','NG5')
cells=defaultdict(lambda:[0,0.0,0.0,0,0.0,0,0.0,0.0]); SK=defaultdict(int); t0=time.time(); ntr=0; ng=0
def put(key,season,r,r3):
    c=cells[key]; c[0]+=1; c[1]+=r; c[2]+=r*r; c[7]+=r3
    if season==2024: c[3]+=1; c[4]+=r
    else: c[5]+=1; c[6]+=r
for i in range(0,len(G),1500):
    sub=G.iloc[i:i+1500]; ids=list(sub.event_id)
    M=pd.read_sql("SELECT event_id,sel,minute,m,ltp::float ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt='MO' AND sel IN ('HOME','AWAY') AND minute BETWEEN 0 AND 2 AND ltp>=1.01 AND ltp<1000",con,params=(ids,))
    M=M.sort_values(['event_id','sel','minute','m']).drop_duplicates(['event_id','sel'])
    fp={}; fm={}
    for r in M.itertuples():
        fp.setdefault(r.event_id,{})[r.sel]=r.ltp
        fm[r.event_id]=min(fm.get(r.event_id,r.m),r.m)
    P=pd.read_sql("SELECT event_id,minute,mkt,sel,m,ltp::float ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt IN ('OU15','OU25','OU35') AND minute BETWEEN 46 AND 95 AND ltp>=1.01 AND ltp<1000",con,params=(ids,))
    P=P.sort_values(['event_id','mkt','sel','minute','m']).drop_duplicates(['event_id','mkt','sel','minute'])
    px={}
    for (eid,mkt,sel),gg in P.groupby(['event_id','mkt','sel'],sort=False):
        arr=np.full(96,np.nan); arr[gg.minute.values]=gg.ltp.values; px.setdefault(eid,{})[(mkt,sel)]=arr
    for g in sub.itertuples():
        if g.event_id in fm:
            lag=(pd.Timestamp(fm[g.event_id])-pd.Timestamp(g.kickoff)).total_seconds()/60
            if lag<-5 or lag>20: SK['game dropped, first MO print off the kick-off']+=1; continue
        b=px.get(g.event_id)
        if not b: SK['game has no OU print after 46']+=1; continue
        ng+=1; f=fp.get(g.event_id,{}); fs=favst(f.get('HOME'),f.get('AWAY'))
        goals=g2.get(g.fixture_id,[]); hg,ag=int(g.hg),int(g.ag); hh,ha=int(g.ht_hg),int(g.ht_ag); s=int(g.season)
        lg=f"{g.league_id} {g.league}"
        for (mkt,sel),arr in b.items():
            if decided(mkt,hh,ha): continue
            d=rp(arr,46,48)
            if d is None: SK['no 46-48 print']+=1; continue
            if goals and goals[0]<d: SK['2H goal before decision']+=1; continue
            won=result(mkt,sel,hg,ag); nx=nxt_goal(goals,d)
            for side in ('B','L'):
                p=fill(arr,d,side)
                if p>50: SK['price over 50']+=1; continue
                for ex in EXITS:
                    if ex=='SETTLE': q=None
                    elif ex=='T70': q=exit_px(arr,70)
                    else:
                        k=2 if ex=='NG2' else 5
                        q=exit_px(arr,nx+k) if nx is not None else None
                    r=pnl(side,p,q,won)
                    if r is None: continue
                    r3=pnl(side,p,q,won,3)
                    if r3 is None: r3=r
                    ntr+=1
                    for fk in ('*',fs):
                        for lk in ('*',lg):
                            put((g.state,mkt,sel,side,ex,fk,lk),s,r,r3)
    print(f"  {min(i+1500,len(G))}/{len(G)} games | priced {ng} | trades {ntr} | cells {len(cells)} | {int(time.time()-t0)}s",flush=True)
print("skips (counted):",dict(SK),flush=True)
R=pd.DataFrame([k+tuple(v) for k,v in cells.items()],columns=['state','mkt','sel','side','exit','fav','league','n','s','ss','n1','s1','n2','s2','s3'])
R['per10']=R.s/R.n; R['sd']=np.sqrt(np.maximum((R.ss/R.n-R.per10**2)*R.n/(R.n-1).replace(0,np.nan),1e-9)); R['t']=R.per10/(R.sd/np.sqrt(R.n))
R['h1']=R.s1/R.n1.replace(0,np.nan); R['h2']=R.s2/R.n2.replace(0,np.nan); R['t3']=R.s3/R.n
R['STD']=(R.n>=300)&(R.n1>=150)&(R.n2>=150)&(R.t>=3.5)&(R.h1>0)&(R.h2>0)&(R.per10>=0.15)
key=['state','mkt','sel','side','fav','league']
ng5=R[R.exit=='NG5'].set_index(key).STD.to_dict()
R['PASS']=[a and (e!='NG2' or ng5.get((b,c,d_,f,g_,h),False)) for a,e,b,c,d_,f,g_,h in zip(R.STD,R.exit,R.state,R.mkt,R.sel,R.side,R.fav,R.league)]
T=R[R.n>=300]; bonf=NormalDist().inv_cdf(1-0.05/max(len(T),1))
cols=['state','mkt','sel','side','exit','fav','league','n','per10','t','n1','h1','n2','h2','t3','PASS']
print(f"\n==== HT FAMILY: {len(R)} cells, {len(T)} with n>=300 (one-sided Bonferroni 5% t = {bonf:.2f}) ====")
print("\n== base table: every HT state x market x side, SETTLE, all leagues, all favourites\n",R[(R.fav=='*')&(R.league=='*')&(R.exit=='SETTLE')].sort_values(['state','mkt','sel','side'])[cols].round(3).to_string(index=False))
print("\n== top 15 by t, n>=300\n",T.sort_values('t',ascending=False).head(15)[cols].round(3).to_string(index=False))
print("\n== top 10 by t, n>=300, favourite split only\n",T[(T.fav!='*')&(T.league=='*')].sort_values('t',ascending=False).head(10)[cols].round(3).to_string(index=False))
print("\n== NAMED (S24-S28 and L2 have no written rule anywhere on this box, so they are covered only as cells of the grid)")
def named(name,**kw):
    d=R
    for k,v in kw.items(): d=d[d[k]==v]
    print(name); print(d[cols].round(3).to_string(index=False) if len(d) else "  no trades")
for ex in EXITS:
    named(f"S13 HT 0-2, home favourite, back O3.5, {ex}",state='0-2',mkt='OU35',sel='OVER',side='B',exit=ex,fav='HF',league='*')
    named(f"S13b HT 0-2, any favourite, back O3.5, {ex}",state='0-2',mkt='OU35',sel='OVER',side='B',exit=ex,fav='*',league='*')
    named(f"S14 HT 1-1, home favourite, back O2.5, {ex}",state='1-1',mkt='OU25',sel='OVER',side='B',exit=ex,fav='HF',league='*')
    named(f"S14b HT 1-1, any favourite, back O2.5, {ex}",state='1-1',mkt='OU25',sel='OVER',side='B',exit=ex,fav='*',league='*')
db=psycopg2.connect(DB,sslmode='require'); dc=db.cursor(); dc.execute("SET statement_timeout='600s'")
dc.execute("DROP TABLE IF EXISTS ht_family_v1; CREATE TABLE ht_family_v1 (state TEXT, mkt TEXT, sel TEXT, side TEXT, exit TEXT, fav TEXT, league TEXT, n INT, s DOUBLE PRECISION, ss DOUBLE PRECISION, n1 INT, s1 DOUBLE PRECISION, n2 INT, s2 DOUBLE PRECISION, s3 DOUBLE PRECISION)")
psycopg2.extras.execute_values(dc,"INSERT INTO ht_family_v1 VALUES %s",[(a,b,c,d_,e,f,g_,int(h),float(i_),float(j),int(k),float(l),int(m_),float(n_),float(o)) for a,b,c,d_,e,f,g_,h,i_,j,k,l,m_,n_,o in R[['state','mkt','sel','side','exit','fav','league','n','s','ss','n1','s1','n2','s2','s3']].itertuples(index=False)],page_size=5000)
dc.execute("SELECT count(*) FROM ht_family_v1"); stored=dc.fetchone()[0]; assert stored==len(R),(stored,len(R)); db.commit(); db.close()
print(f"stored ht_family_v1: {stored} rows in one transaction")
S=R[R.PASS].sort_values('t',ascending=False)
print(f"\n== SURVIVORS: {len(S)} (of {len(T)} cells at n>=300; STD before the NG5 test: {int(R.STD.sum())})")
print(S[cols].round(3).to_string(index=False) if len(S) else "none")
PY
