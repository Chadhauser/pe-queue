#!/bin/bash
set -o pipefail
# 499_fh_share (Finder 2026-11-07, queue item 336, Finder's own, source c; entry from jobs/499_table_v_price.sh): a team's own first-half share of goals against FH05 and FH15. Rule pushed in the queue before any price. Read only, no tables written. LTP only, so a pass is an upper bound.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(1_800_000_000,1_800_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import defaultdict,deque
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line
from lib_official import bk,ly,secs,checks
import lib_cand; lib_cand._checks(); checks()
pd.set_option('display.width',230); pd.set_option('display.max_rows',80); pd.set_option('display.max_columns',30)
T0=time.time()
def rolling(games,k=10):
    """games: time-ordered (fid,secs,home,away,fh_goals,all_goals), one league-season. fid->mean of the two teams' FHS over their last k games; same-time games are not history for each other; no goals in a team's window = not scored."""
    H=defaultdict(lambda:deque(maxlen=k)); out={}; i=0
    while i<len(games):
        j=i
        while j<len(games) and games[j][1]==games[i][1]: j+=1
        for f,t,h,a,fh,al in games[i:j]:
            if len(H[h])==k and len(H[a])==k:
                x=sum(z[1] for z in H[h]); y=sum(z[1] for z in H[a])
                if x>0 and y>0: out[f]=(sum(z[0] for z in H[h])/x+sum(z[0] for z in H[a])/y)/2
        for f,t,h,a,fh,al in games[i:j]:
            H[h].append((fh,al)); H[a].append((fh,al))
        i=j
    return out
# hand-worked with k=2: A and B meet twice, 1 of 2 goals then 0 of 2, FHS 1/4 each; game 3 value 0.25
_o=rolling([(1,10,'A','B',1,2),(2,20,'B','A',0,2),(3,30,'A','B',9,9)],2); assert list(_o)==[3] and abs(_o[3]-.25)<1e-9
assert rolling([(1,10,'A','B',0,0),(2,20,'B','A',0,0),(3,30,'A','B',1,1)],2)=={}      # no goals in the window, not scored
assert rolling([(1,10,'A','B',1,2),(2,10,'B','A',1,2),(3,10,'A','B',1,1)],2)=={}      # same kick-off time is not history
assert rolling([(1,10,'A','B',1,2),(3,30,'A','B',1,1)],2)=={}                          # too few games
print("checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
F=pd.read_sql("SELECT fixture_id,league_id,season,kickoff,home,away,hg,ag,ht_hg,ht_ag FROM af_fixtures WHERE status='FT' AND hg IS NOT NULL AND ht_hg IS NOT NULL AND ht_ag IS NOT NULL AND season IN (2023,2024,2025)",con)
F['tt']=secs(F.kickoff); F['fh']=F.ht_hg+F.ht_ag; F['al']=F.hg+F.ag; bad_ht=F.fh>F.al; print("fixtures",len(F),"half-time score above full-time, dropped",int(bad_ht.sum()),flush=True); F=F[~bad_ht]
R={}
for (l,s),g in F.sort_values('tt').groupby(['league_id','season']):
    R.update(rolling([tuple(x) for x in g[['fixture_id','tt','home','away','fh','al']].itertuples(index=False)]))
ST=pd.DataFrame({'fixture_id':list(R),'fhs':list(R.values())}).merge(F[['fixture_id','season']],on='fixture_id')
A,B=ST[ST.season==2023].fhs.quantile(.2),ST[ST.season==2023].fhs.quantile(.8)
print("games with a value by season",ST.season.value_counts().to_dict(),"cuts on 2023 (20th, 80th)",round(A,4),round(B,4),"share of 2024-25 HIGH",round((ST[ST.season>2023].fhs>=B).mean(),3),"LOW",round((ST[ST.season>2023].fhs<=A).mean(),3),flush=True)
assert 0<A<B<1
G=pd.read_sql("SELECT m.event_id,f.fixture_id,f.kickoff,f.ht_hg,f.ht_ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.ht_hg IS NOT NULL AND f.ht_ag IS NOT NULL AND f.season IN (2024,2025)",con)
G=G[G.fixture_id.isin(R)]
NMS=pd.read_sql("SELECT DISTINCT ON (event_id) event_id,event_name FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt='MO'",con,params=(list(G.event_id),))
BAD=NMS.event_name.str.contains(r"U-?(?:1[5-9]|2[0-3])\b|\(W\)|\bWomen\b| II\b| B(?: v |$)| Reserves?(?: v |$)|^Jong | v Jong ",regex=True); bad=set(NMS.event_id[BAD]); print('maps naming a youth, women or reserve game, dropped',len(bad),flush=True); G=G[~G.event_id.isin(bad)]
EV=pd.read_sql("SELECT fixture_id,min(coalesce(minute,0)) gm FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal') AND coalesce(minute,0)<=2 GROUP BY 1",con,params=(list(map(int,G.fixture_id)),))
fg=dict(zip(EV.fixture_id,EV.gm)); parts=[]
for i in range(0,len(G),1000):
    P=pd.read_sql("SELECT event_id,mkt,sel,minute,m,ltp::float8 ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt IN ('FH05','FH15') AND sel IN ('OVER','UNDER') AND minute>=0 AND minute<=2 AND ltp>=1.01 AND ltp<1000",con,params=(list(G.event_id.iloc[i:i+1000]),))
    parts.append(P.sort_values(['event_id','mkt','sel','minute','m']).drop_duplicates(['event_id','mkt','sel']))
con.close(); P=pd.concat(parts,ignore_index=True).merge(G[['event_id','fixture_id','kickoff']],on='event_id')
lag=(pd.to_datetime(P.m,utc=True)-pd.to_datetime(P.kickoff,utc=True))/pd.Timedelta(minutes=1); gm=P.fixture_id.map(fg)
bad=(lag<-5)|(lag>20)|(gm.notna()&(gm<P.minute)); print(f"rows dropped by the guards {int(bad.sum())} of {len(P)}",flush=True); P=P[~bad]
P['k']=P.mkt+'_'+P.sel
W=P.pivot_table(index='event_id',columns='k',values='ltp',aggfunc='first').reset_index()
D=G.merge(W,on='event_id').sort_values('kickoff').drop_duplicates('fixture_id'); D['fhs']=D.fixture_id.map(R); D['off']=secs(D.kickoff); D['fh']=D.ht_hg+D.ht_ag; md=float(np.median(D.off))
print("games",len(D),"with",{c:int(D[c].notna().sum()) for c in W.columns if c!='event_id'},flush=True)
out=[]; ctrl={}
def add(nm,x,pc,won,base=False):
    x=x[x[pc].notna()]; w=won(x).astype(bool).values; pr=x[pc].values
    for side,f in (('back',bk),('lay',ly)):
        v=np.array([np.nan if (q:=f(float(p),bool(y))) is None else q for p,y in zip(pr,w)],dtype=float); m=np.isfinite(v); v2=v[m]
        if base: ctrl[(pc,side)]=v2
        if m.sum()<30: out.append(dict(line=f'{nm} {pc} {side}',n=int(m.sum()),PASS=False)); continue
        l=line(v2,np.where(x.off.values[m]<md,1,2)); nv=ctrl.get((pc,side)); dt=np.nan
        if not base and nv is not None: dt=(v2.mean()-nv.mean())/np.sqrt(v2.var(ddof=1)/len(v2)+nv.var(ddof=1)/len(nv))
        out.append(dict(line=f'{nm} {pc} {side}',n=l['n'],per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],maxwin=l['maxwin'],won=w[m].mean(),imp=(1/pr[m]).mean(),t_v_ctrl=dt,PASS=l['PASS'] and not base))
WON={'FH05_OVER':lambda x:x.fh>0.5,'FH05_UNDER':lambda x:x.fh<0.5,'FH15_OVER':lambda x:x.fh>1.5,'FH15_UNDER':lambda x:x.fh<1.5}
for pc,fn in WON.items():
    add('CONTROL all',D,pc,fn,True); add('HIGH',D[D.fhs>=B],pc,fn); add('LOW',D[D.fhs<=A],pc,fn)
L=pd.DataFrame(out); print(f"\nlines {len(L)}, scored {int((~L.line.str.startswith('CONTROL')).sum())}, at n>=300 {int((L.n>=300).sum())}, {time.time()-T0:.0f}s"); print(L.sort_values('t',ascending=False).round(3).drop(columns=['n1','n2']).to_string(index=False))
S_=L[L.PASS==True]
print(f"\n== SURVIVORS: {len(S_)}\n",S_.round(3).to_string(index=False) if len(S_) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
