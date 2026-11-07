#!/bin/bash
set -o pipefail
# 499_foul_rel_seen (Finder 2026-11-07, queue item 341, Finder's own, source d; FOUL from jobs/499_style_raw.sh, FOUL_REL from jobs/499_foul_draw_league.sh, entry from jobs/499_table_v_price.sh): the Draw where fouls are high and high for the league, on item 335's games. Rule pushed in the queue before this read. Read only, no tables written. LTP only, so a pass is an upper bound.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(1_800_000_000,1_800_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import defaultdict,deque
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line
from lib_official import bk,secs,checks
import lib_cand; lib_cand._checks(); checks()
pd.set_option('display.width',230); pd.set_option('display.max_columns',30)
T0=time.time(); FOUL_CUT=26.6; REL_CUT=1.0582
def foul_state(games):
    """As jobs/499_foul_draw_unseen.sh. games: time-ordered (fid,secs,home,away,hf,af), one league-season."""
    H=defaultdict(lambda:deque(maxlen=5)); out={}; i=0
    while i<len(games):
        j=i
        while j<len(games) and games[j][1]==games[i][1]: j+=1
        for f,t,h,a,hf,af in games[i:j]:
            if len(H[h])==5 and len(H[a])==5: out[f]=(sum(H[h])/5+sum(H[a])/5)/2
        for f,t,h,a,hf,af in games[i:j]:
            if hf==hf and af==af: H[h].append(hf+af); H[a].append(hf+af)
        i=j
    return out
def rel(s):
    """Value over the mean of earlier values, at least 50 earlier."""
    return s/s.shift().expanding(min_periods=50).mean()
assert foul_state([(i,i*10,'A','B',10.,14.) for i in range(1,6)]+[(6,60,'A','B',0.,0.)])=={6:24.0}
assert foul_state([(i,10,'A','B',10.,14.) for i in range(1,7)])=={}
_r=rel(pd.Series([20.]*50+[26.,30.])); assert _r.iloc[:50].isna().all() and abs(_r.iloc[50]-1.3)<1e-9 and abs(_r.iloc[51]-30/(1026/51))<1e-9
print("checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
S=pd.read_sql("SELECT f.fixture_id,f.league_id,f.season,f.kickoff,f.home,f.away,s.is_home,(s.raw->>'Fouls')::float fl FROM af_fixtures f JOIN af_stats s USING(fixture_id) WHERE f.status='FT' AND f.hg IS NOT NULL AND f.season IN (2023,2024,2025)",con)
F=S[S.is_home==True].merge(S[S.is_home==False][['fixture_id','fl']],on='fixture_id',suffixes=('_h','_a')).drop_duplicates('fixture_id'); F['tt']=secs(F.kickoff); R={}
for (l,s_),g in F.sort_values('tt').groupby(['league_id','season']):
    R.update(foul_state([tuple(x) for x in g[['fixture_id','tt','home','away','fl_h','fl_a']].itertuples(index=False)]))
F['fv']=F.fixture_id.map(R); F=F.sort_values('tt')
F['rel']=F.groupby(['league_id','season']).fv.transform(lambda z:rel(z.dropna()).reindex(z.index))
_c=F[(F.season==2023)&F.fv.notna()].fv.quantile(.8); print("re-derived cuts: FOUL",round(_c,3),flush=True); assert abs(_c-FOUL_CUT)<1e-6
G=pd.read_sql("SELECT m.event_id,f.fixture_id,f.kickoff,f.hg,f.ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL AND f.season IN (2024,2025)",con)
G=G[G.fixture_id.isin(R)]
NMS=pd.read_sql("SELECT DISTINCT ON (event_id) event_id,event_name FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt='MO' AND sel='HOME' AND minute=1",con,params=(list(G.event_id),))
BAD=NMS.event_name.str.contains(r"U-?(?:1[5-9]|2[0-3])\b|\(W\)|\bWomen\b| II\b| B(?: v |$)| Reserves?(?: v |$)|^Jong | v Jong ",regex=True); bad=set(NMS.event_id[BAD]); print('maps naming a youth, women or reserve game, dropped',len(bad),flush=True); G=G[~G.event_id.isin(bad)]
EV=pd.read_sql("SELECT fixture_id,min(coalesce(minute,0)) gm FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal') AND coalesce(minute,0)<=2 GROUP BY 1",con,params=(list(map(int,G.fixture_id)),))
fg=dict(zip(EV.fixture_id,EV.gm)); parts=[]
for i in range(0,len(G),1000):
    P=pd.read_sql("SELECT event_id,minute,m,ltp::float8 ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt='MO' AND sel='DRAW' AND minute>=0 AND minute<=2 AND ltp>=1.01 AND ltp<1000",con,params=(list(G.event_id.iloc[i:i+1000]),))
    parts.append(P.sort_values(['event_id','minute','m']).drop_duplicates('event_id'))
con.close(); P=pd.concat(parts,ignore_index=True).merge(G[['event_id','fixture_id','kickoff']],on='event_id')
lag=(pd.to_datetime(P.m,utc=True)-pd.to_datetime(P.kickoff,utc=True))/pd.Timedelta(minutes=1); gm=P.fixture_id.map(fg)
bad=(lag<-5)|(lag>20)|(gm.notna()&(gm<P.minute)); print(f"rows dropped by the guards {int(bad.sum())} of {len(P)}",flush=True); P=P[~bad]
D=G.merge(P[['event_id','ltp']],on='event_id').sort_values('kickoff').drop_duplicates('fixture_id').merge(F[['fixture_id','fv','rel']],on='fixture_id')
D['off']=secs(D.kickoff); md=float(np.median(D.off)); D['won']=D.hg==D.ag; print("games",len(D),"with REL",int(D.rel.notna().sum()),flush=True)
D=D[D.rel.notna()]
D['v']=[bk(float(p),bool(w)) for p,w in zip(D.ltp,D.won)]; D=D[D.v.notna()]
FH=D.fv>=FOUL_CUT; RH=D.rel>=REL_CUT; o=[]
def rd(nm,x,sc):
    l=line(x.v.values.astype(float),np.where(x.off.values<md,1,2)); o.append(dict(line=nm,n=l['n'],per10=round(l['per10'],3),t=round(l['t'],2),h1=round(l['h1'],3),h2=round(l['h2'],3),n1=l['n1'],n2=l['n2'],maxwin=round(l['maxwin'],2),won=round(x.won.mean(),3),imp=round((1/x.ltp).mean(),3),PASS=l['PASS'] and sc))
rd('REL HIGH and FOUL HIGH',D[FH&RH],True); rd('FOUL HIGH only',D[FH&~RH],False); rd('REL HIGH only',D[~FH&RH],False); rd('neither',D[~FH&~RH],False); rd('all with REL',D,False)
L=pd.DataFrame(o); print(L.to_string(index=False)); S_=L[L.PASS]
print(f"\n== SURVIVORS: {len(S_)}\n",S_.to_string(index=False) if len(S_) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
