#!/bin/bash
set -o pipefail
# 499_backup_keeper (Finder 2026-11-05, queue item 89, Finder's own, source d): is a back-up keeper priced at the first in-play print? Rule written in the queue before any price was read. Entry and guards from jobs/499_team_form_stage.sh. The number 499 is reused with a new slug: 450-499 are all taken.
# DATA af_player_stats (position G), af_fixtures, af_price_map, bf_hist_price. Player stats on mapped games are 2025 only, so halves are by date median.
# STATE BACKUP: today's keeper played 85+ minutes, so an injury or red-card replacement cannot flag it; he played no minutes as keeper in the team's previous 5 games on the box; 3+ such games held. The minutes are read after the game, but they stand for the team sheet: a keeper sent off or injured late (85+) is the one leak left.
# ENTRY earliest real print in tape minutes 0..2, lag outside -5..+20 min dropped, a goal strictly before the print dropped, one tick adverse, 2%, £10 risk, hold to FT.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import defaultdict,deque
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import *
import lib_cand; lib_cand._checks()
pd.set_option('display.width',250); pd.set_option('display.max_rows',300); pd.set_option('display.max_columns',40)
T0=time.time()
def flags(games):
    """games: oldest first, (fixture,team,{keeper_id:minutes}). {(fixture,team):'BACKUP'|'NOT_BACKUP'} where 3+ earlier games are held. Games at the same kick-off do not arise for one team."""
    hist=defaultdict(lambda:deque(maxlen=5)); out={}
    for f,t,ks in games:
        H=hist[t]
        if len(H)>=3 and ks:
            main=[p for p,m in ks.items() if m>=85]
            if len(main)==1:
                seen=set().union(*H); out[(f,t)]='BACKUP' if main[0] not in seen else 'NOT_BACKUP'
        hist[t].append({p for p,m in ks.items() if m>0})
    return out
def bk(x,won):
    a=step(x,-1); return None if a<=1.01 else back_settle(a,won)
def ly(x,won): return lay_settle(step(x,1),won)
# known answers
_g=[(i,'A',{7:90}) for i in range(1,5)]+[(5,'A',{9:90}),(6,'A',{7:30,9:60}),(7,'A',{7:90}),(8,'B',{1:90})]
_f=flags(_g)
assert (1,'A') not in _f and (3,'A') not in _f and _f[(4,'A')]=='NOT_BACKUP' and _f[(5,'A')]=='BACKUP'
assert (6,'A') not in _f                      # nobody played 85+: a mid-game change cannot flag it
assert _f[(7,'A')]=='NOT_BACKUP' and (8,'B') not in _f
_h=[(i,'C',{7:90}) for i in range(1,7)]+[(7,'C',{9:90}),(8,'C',{9:90})]
_f=flags(_h); assert _f[(7,'C')]=='BACKUP' and _f[(8,'C')]=='NOT_BACKUP'  # played last game, so not new
assert abs(bk(2.04,True)-9.996)<1e-9 and bk(2.04,False)==-10.0 and ly(2.0,True)==-10.0 and abs(ly(2.0,False)-10/1.02*.98)<1e-9 and bk(1.01,True) is None
print("checks: OK",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
K=pd.read_sql("SELECT s.fixture_id,s.team,s.player_id,s.minutes,f.kickoff,f.league_id,f.season,f.home,f.away FROM af_player_stats s JOIN af_fixtures f USING(fixture_id) WHERE s.position='G' AND coalesce(s.minutes,0)>0 AND f.status='FT'",con)
K['ks']=pd.to_datetime(K.kickoff,utc=True)
print(f"keeper rows {len(K)}, fixtures {K.fixture_id.nunique()}, {K.ks.min()} .. {K.ks.max()}; teams not home or away {int(((K.team!=K.home)&(K.team!=K.away)).sum())}",flush=True)
games=[]
for (ks,f,t),x in K.sort_values(['ks','fixture_id']).groupby(['ks','fixture_id','team'],sort=False):
    games.append((f,t,dict(zip(x.player_id,x.minutes))))
FL=flags(games); vc=pd.Series(FL).value_counts().to_dict(); print("flags",vc,flush=True)
ALLF=pd.read_sql("SELECT league_id,season,home,away FROM af_fixtures WHERE status='FT' AND season IN (2024,2025)",con)
cnt=pd.concat([ALLF[['league_id','season','home']].rename(columns={'home':'t'}),ALLF[['league_id','season','away']].rename(columns={'away':'t'})]).groupby(['league_id','season','t']).size()
ids=list({f for f,_ in FL})
G=pd.read_sql("""SELECT m.event_id,f.fixture_id,f.league_id,f.season,f.kickoff,f.home,f.away,f.hg,f.ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL AND f.fixture_id=ANY(%s)""",con,params=(ids,))
print(f"mapped games with a flag {len(G)}",flush=True)
EV=pd.read_sql("SELECT fixture_id,min(coalesce(minute,0)) gm FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal') AND coalesce(minute,0)<=2 GROUP BY 1",con,params=(list(map(int,G.fixture_id)),))
first_goal=dict(zip(EV.fixture_id,EV.gm)); parts=[]
for i in range(0,len(G),1000):
    P=pd.read_sql("SELECT event_id,mkt,sel,minute,m,ltp::float ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt IN ('MO','OU25') AND sel IN ('HOME','AWAY','UNDER','OVER') AND minute>=0 AND minute<=2 AND ltp>=1.01 AND ltp<1000",con,params=(list(G.event_id.iloc[i:i+1000]),))
    parts.append(P.sort_values(['event_id','mkt','sel','minute','m']).drop_duplicates(['event_id','mkt','sel']))
con.close()
P=pd.concat(parts,ignore_index=True).merge(G,on='event_id')
P['lag']=(pd.to_datetime(P.m,utc=True)-pd.to_datetime(P.kickoff,utc=True)).dt.total_seconds()/60
bad=(P.lag<-5)|(P.lag>20); gm=P.fixture_id.map(first_goal); kn=gm.notna()&(gm<P.minute)
print(f"games with a print {P.event_id.nunique()}; rows dropped, lag {int(bad.sum())}, goal known before the print {int(kn.sum())}; {time.time()-T0:.0f}s",flush=True); P=P[~bad&~kn]
med=pd.to_datetime(P.drop_duplicates('event_id').kickoff,utc=True).sort_values().iloc[P.event_id.nunique()//2]; print("halves split at",med,flush=True)
rows=[]
for (e,fx,lg,s,ko,ho,aw,hg,ag),x in P.groupby(['event_id','fixture_id','league_id','season','kickoff','home','away','hg','ag']):
    pr=dict(zip(x.sel,x.ltp)); over=hg+ag>2.5; hf=1 if pd.to_datetime(ko,utc=True)<=med else 2
    for team,opp,sel,osel,won,owon in ((ho,aw,'HOME','AWAY',hg>ag,ag>hg),(aw,ho,'AWAY','HOME',ag>hg,hg>ag)):
        st=FL.get((fx,team))
        if st is None: continue
        lgm=cnt.get((lg,s,team),0)>=20
        for sp in ['all']+(['league'] if lgm else []):
            def add(leg,side,v):
                if v is not None: rows.append((st,sp,leg,side,hf,e,v))
            if sel in pr: add('TEAM','BACK',bk(pr[sel],won)); add('TEAM','LAY',ly(pr[sel],won))
            if osel in pr: add('OPP','BACK',bk(pr[osel],owon)); add('OPP','LAY',ly(pr[osel],owon))
            if 'OVER' in pr: add('OVER','BACK',bk(pr['OVER'],over)); add('OVER','LAY',ly(pr['OVER'],over))
            if 'UNDER' in pr: add('UNDER','BACK',bk(pr['UNDER'],not over)); add('UNDER','LAY',ly(pr['UNDER'],not over))
T=pd.DataFrame(rows,columns=['state','split','leg','side','h','g','v']); o=[]
for k,x in T.groupby(['state','split','leg','side']):
    d=line(x.v.values,x.h.values); o.append(dict(zip(['state','split','leg','side'],k))|dict(n=d['n'],games=x.g.nunique(),per10=round(d['per10'],3),t=round(d['t'],2),h1=round(d['h1'],3),h2=round(d['h2'],3),n1=d['n1'],n2=d['n2'],PASS=d['PASS']))
L=pd.DataFrame(o); print(f"\nlines {len(L)}, at n>=300 {(L.n>=300).sum()}, passing {int(L.PASS.sum())}, {time.time()-T0:.0f}s")
print("\nALL LINES by state and t"); print(L.sort_values(['state','t'],ascending=[True,False]).drop(columns=['n1','n2']).to_string(index=False))
print("\nSURVIVORS"); S=L[L.PASS]; print(S.to_string(index=False) if len(S) else "none")
print(f"done {time.time()-T0:.0f}s")
PY
