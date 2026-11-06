#!/bin/bash
set -o pipefail
# 499_rotation_scorer (Finder 2026-11-06, queue items 248, 249, 250; Finder's own, sources a and d; from jobs/499_backup_keeper.sh): rotation and the top scorer at the first in-play print. Rules pushed in the queue before any price was read. Read only.
# DATA af_player_stats, af_fixtures, af_price_map, af_events, bf_hist_price. Player stats on mapped games start 10 Jan 2026, so halves are by date median, one season.
# RESTED counts men with 60+ minutes last time and 0 today: 0 minutes means not started, so nothing inside the game can cause it (a late substitute lowers it, which is the one leak). S_BACK reads minutes > 0 today and is an upper bound for the same reason.
# ENTRY earliest real print in tape minutes 0..2, lag outside -5..+20 min dropped, a goal strictly before the print dropped, one tick adverse, 2%, £10 risk, hold to FT.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,warnings,pandas as pd,numpy as np
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,back_settle,lay_settle,line,tstat
import lib_cand; lib_cand._checks()
pd.set_option('display.width',230); pd.set_option('display.max_rows',300); pd.set_option('display.max_columns',40)
T0=time.time(); DAY=86400.0
def rested_state(prev,today):
    """prev, today: {player:(minutes,goals)}. Count of 60+ men last time with 0 today."""
    c=sum(1 for p,v in prev.items() if v[0]>=60 and today.get(p,(0,0))[0]==0)
    return 'R0_1' if c<=1 else ('R2_3' if c<=3 else 'R4P')
def top_scorer(H):
    """H: earlier games, each {player:(minutes,goals)}. Unique leader, 3+ goals, 3+ appearances, else None."""
    g={}; a={}
    for x in H:
        for p,v in x.items():
            g[p]=g.get(p,0)+v[1]; a[p]=a.get(p,0)+(v[0]>0)
    if not g: return None
    m=max(g.values())
    if m<3: return None
    w=[p for p,v in g.items() if v==m]
    return w[0] if len(w)==1 and a[w[0]]>=3 else None
def scorer_state(H,today):
    t=top_scorer(H)
    if t is None: return None
    now=today.get(t,(0,0))[0]>0; last=H[-1].get(t,(0,0))[0]>0
    return {(False,True):'S_OUT',(False,False):'S_OUT_LONG',(True,True):'S_IN',(True,False):'S_BACK'}[(now,last)]
def flags(games):
    """games oldest first: (fixture,team,ts seconds,{player:(minutes,goals)}). {(fixture,team):[states]}. Previous game within 14 days; scorer window last 8 within 60 days, 5+ held; both sides of the rested count need 800+ team minutes."""
    hist={}; out={}
    for f,t,ts,d in games:
        H=hist.setdefault(t,[]); st=[]
        if H and ts-H[-1][0]<=14*DAY:
            pv=H[-1][1]
            if sum(v[0] for v in pv.values())>=800 and sum(v[0] for v in d.values())>=800: st.append(rested_state(pv,d))
            W=[x[1] for x in H[-8:] if ts-x[0]<=60*DAY]
            if len(W)>=5:
                s=scorer_state(W,d)
                if s: st.append(s)
        if st: out[(f,t)]=st
        H.append((ts,d))
    return out
def secs(x): return (pd.to_datetime(x,utc=True)-pd.Timestamp('1970-01-01',tz='UTC'))/pd.Timedelta(seconds=1)  # not astype('int64'): its unit depends on the column
def bk(x,won):
    a=step(x,-1); return None if a<=1.01 else back_settle(a,won)
def ly(x,won): return lay_settle(step(x,1),won)
# known answers, worked by hand
_p={i:(90,0) for i in range(11)}
assert rested_state(_p,{i:(90,0) for i in range(11)})=='R0_1'
assert rested_state(_p,{i:(90,0) for i in range(9)})=='R2_3'                    # two absent
assert rested_state(_p,{**{i:(90,0) for i in range(7)},7:(0,0),8:(0,0)})=='R4P'  # 7,8 on the bench unused, 9,10 absent: four
assert rested_state({1:(59,0),2:(60,0)},{})=='R0_1'                             # the 59-minute man does not count
assert rested_state(_p,{**{i:(20,0) for i in range(11)}})=='R0_1'               # all came on late: 0 minutes is the only test
_w=[{9:(90,1),8:(90,0)},{9:(90,1),8:(90,0)},{9:(90,1),8:(90,0)},{9:(0,0),8:(90,0)},{9:(90,0),8:(90,0)}]
assert top_scorer(_w)==9 and top_scorer(_w[:2]) is None                         # 3 goals v 2
assert scorer_state(_w,{8:(90,0)})=='S_OUT' and scorer_state(_w,{9:(90,0)})=='S_IN'
_x=_w[:-1]; assert scorer_state(_x,{9:(70,0)})=='S_BACK' and scorer_state(_x,{8:(90,0)})=='S_OUT_LONG'
assert top_scorer([{9:(90,2),8:(90,2)},{9:(90,1),8:(90,1)},{9:(90,0),8:(90,0)}]) is None  # tied, no flag
assert top_scorer([{9:(90,3)},{9:(0,0)},{9:(0,0)}]) is None                     # fewer than 3 appearances
_full={i:(90,0) for i in range(11)}; _g=[(i,'A',float(i)*7*DAY,_full) for i in range(1,8)]
_f=flags(_g); assert (1,'A') not in _f and _f[(2,'A')]==['R0_1'] and (7,'A') in _f
_f=flags([(1,'A',0.0,_full),(2,'A',15*DAY,_full)]); assert (2,'A') not in _f      # 15-day gap: no previous game
assert abs(bk(2.04,True)-9.996)<1e-9 and bk(2.04,False)==-10.0 and ly(2.0,True)==-10.0 and abs(ly(2.0,False)-10/1.02*.98)<1e-9 and bk(1.01,True) is None
assert float(secs(pd.Series(['2026-01-02 00:00:00+00:00'])).iloc[0])==1767312000.0
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
K=pd.read_sql("SELECT s.fixture_id,s.team,s.player_id,COALESCE(s.minutes,0) minutes,COALESCE(s.goals,0) goals,f.kickoff FROM af_player_stats s JOIN af_fixtures f USING(fixture_id) WHERE f.status IN ('FT','AET','PEN') AND s.player_id IS NOT NULL",con)
K=K.groupby(['fixture_id','team','player_id','kickoff'],as_index=False).agg(minutes=('minutes','max'),goals=('goals','max'))
K['ts']=secs(K.kickoff)
print(f"player rows {len(K):,}, fixtures {K.fixture_id.nunique():,}, {K.kickoff.min()} .. {K.kickoff.max()}",flush=True)
games=[]
for (ts,f,t),x in K.sort_values(['ts','fixture_id']).groupby(['ts','fixture_id','team'],sort=False):
    games.append((int(f),t,ts,{int(p):(int(m),int(g)) for p,m,g in zip(x.player_id,x.minutes,x.goals)}))
FL=flags(games); vc={}
for v in FL.values():
    for s in v: vc[s]=vc.get(s,0)+1
print("team-games by state",dict(sorted(vc.items())),flush=True)
ids=list({f for f,_ in FL})
G=pd.read_sql("""SELECT m.event_id,f.fixture_id,f.league_id,f.season,f.kickoff,f.home,f.away,f.hg,f.ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL AND f.fixture_id=ANY(%s)""",con,params=(ids,))
print(f"mapped FT games with a flag {len(G):,}",flush=True)
EV=pd.read_sql("SELECT fixture_id,min(coalesce(minute,0)) gm FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal') AND coalesce(minute,0)<=2 GROUP BY 1",con,params=(list(map(int,G.fixture_id)),))
first_goal=dict(zip(EV.fixture_id,EV.gm)); parts=[]
for i in range(0,len(G),1000):
    P=pd.read_sql("SELECT event_id,mkt,sel,minute,m,ltp::float ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt IN ('MO','OU25') AND sel IN ('HOME','AWAY','UNDER','OVER') AND minute>=0 AND minute<=2 AND ltp>=1.01 AND ltp<1000",con,params=(list(G.event_id.iloc[i:i+1000]),))
    parts.append(P.sort_values(['event_id','mkt','sel','minute','m']).drop_duplicates(['event_id','mkt','sel']))
con.close()
P=pd.concat(parts,ignore_index=True).merge(G,on='event_id')
P['lag']=(pd.to_datetime(P.m,utc=True)-pd.to_datetime(P.kickoff,utc=True)).dt.total_seconds()/60
bad=(P.lag<-5)|(P.lag>20); gm=P.fixture_id.map(first_goal); kn=gm.notna()&(gm<P.minute)
print(f"games with a print {P.event_id.nunique():,}; rows dropped, lag {int(bad.sum())}, goal known before the print {int(kn.sum())}; {time.time()-T0:.0f}s",flush=True); P=P[~bad&~kn]
med=pd.to_datetime(P.drop_duplicates('event_id').kickoff,utc=True).sort_values().iloc[P.event_id.nunique()//2]; print("halves split at",med,flush=True)
rows=[]
for (e,fx,ko,ho,aw,hg,ag),x in P.groupby(['event_id','fixture_id','kickoff','home','away','hg','ag']):
    pr=dict(zip(x.sel,x.ltp)); over=hg+ag>2.5; hf=1 if pd.to_datetime(ko,utc=True)<=med else 2
    for team,sel,osel,won,owon in ((ho,'HOME','AWAY',hg>ag,ag>hg),(aw,'AWAY','HOME',ag>hg,hg>ag)):
        for st in FL.get((int(fx),team),[]):
            bands=['ALL']
            if sel in pr:
                if pr[sel]<=2.0: bands.append('FAV')
                if pr[sel]>=3.0: bands.append('DOG')
            for b in bands:
                def add(leg,side,v):
                    if v is not None: rows.append((st,b,leg,side,hf,e,v))
                if sel in pr: add('TEAM','BACK',bk(pr[sel],won)); add('TEAM','LAY',ly(pr[sel],won))
                if osel in pr: add('OPP','BACK',bk(pr[osel],owon)); add('OPP','LAY',ly(pr[osel],owon))
                if 'OVER' in pr: add('OVER','BACK',bk(pr['OVER'],over)); add('OVER','LAY',ly(pr['OVER'],over))
                if 'UNDER' in pr: add('UNDER','BACK',bk(pr['UNDER'],not over)); add('UNDER','LAY',ly(pr['UNDER'],not over))
T=pd.DataFrame(rows,columns=['state','band','leg','side','h','g','v'])
gl=T.leg.isin(['OVER','UNDER']); T=pd.concat([T[~gl],T[gl].drop_duplicates(['state','band','leg','side','g'])],ignore_index=True)  # goal lines: one bet per game per line
o=[]
for k,x in T.groupby(['state','band','leg','side']):
    d=line(x.v.values,x.h.values); tg=tstat(x.groupby('g').v.sum().values)
    o.append(dict(zip(['state','band','leg','side'],k))|dict(n=d['n'],games=x.g.nunique(),per10=round(d['per10'],3),t=round(d['t'],2),tg=round(tg,2),h1=round(d['h1'],3),h2=round(d['h2'],3),n1=d['n1'],n2=d['n2'],PASS=bool(d['PASS'] and tg>=3.5)))
L=pd.DataFrame(o); print(f"\nlines {len(L)}, at n>=300 {(L.n>=300).sum()}, passing {int(L.PASS.sum())}, {time.time()-T0:.0f}s")
for nm,ss in (('248 ROTATION',['R0_1','R2_3','R4P']),('249 SCORER OUT',['S_OUT','S_OUT_LONG','S_IN']),('250 SCORER BACK',['S_BACK'])):
    print(f"\n== {nm}, top 15 by t"); print(L[L.state.isin(ss)].sort_values('t',ascending=False).head(15).drop(columns=['n1','n2']).to_string(index=False))
print("\n== controls: every line for R0_1 and S_IN, ALL"); print(L[L.state.isin(['R0_1','S_IN'])&(L.band=='ALL')].drop(columns=['n1','n2']).to_string(index=False))
print("\nSURVIVORS"); S=L[L.PASS]; print(S.to_string(index=False) if len(S) else "none")
print(f"done {time.time()-T0:.0f}s")
PY
