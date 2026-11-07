#!/bin/bash
set -o pipefail
# 499_style_off_saves (Finder 2026-11-07, queue item 346, Finder's own, source d; engine from jobs/499_style_raw.sh): offsides and keeper saves against the first in-play price. Rule pushed in the queue before any price. Read only, no tables written. LTP only, so a pass is an upper bound.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(1_800_000_000,1_800_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import defaultdict,deque
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line
from lib_official import bk,ly,secs,checks
import lib_cand; lib_cand._checks(); checks()
pd.set_option('display.width',230); pd.set_option('display.max_rows',120); pd.set_option('display.max_columns',30)
T0=time.time()
def rolling(games):
    """games: time-ordered (fid,secs,home,away,ho,ao,hs,as_), floats or nan; one league-season. fid->(OFF,SAVE,busy home,busy away). A team needs 5 earlier complete games; same-time games are not history for each other."""
    H=defaultdict(lambda:deque(maxlen=5)); out={}; i=0
    while i<len(games):
        j=i
        while j<len(games) and games[j][1]==games[i][1]: j+=1
        for g in games[i:j]:
            f,k,h,a=g[:4]
            if len(H[h])==5 and len(H[a])==5:
                x=np.array(H[h]); y=np.array(H[a])
                out[f]=((x[:,0].mean()+y[:,0].mean())/2,(x[:,1].mean()+y[:,1].mean())/2,x[:,2].mean(),y[:,2].mean())
        for g in games[i:j]:
            f,k,h,a,ho,ao,hs,as_=g
            if all(v==v for v in (ho,ao,hs,as_)):
                H[h].append((ho+ao,hs+as_,hs)); H[a].append((ho+ao,hs+as_,as_))
        i=j
    return out
# hand-worked: five games with 2+1 offsides and home keeper 4 saves, away keeper 2: OFF 3, SAVE 6, busy A 4, busy B 2
_g=[(i,i*10,'A','B',2.,1.,4.,2.) for i in range(1,6)]+[(6,60,'A','B',9.,9.,9.,9.)]
_o=rolling(_g); assert list(_o)==[6] and _o[6]==(3.0,6.0,4.0,2.0)
# a missing stat adds no history; same-time games are not history
_g2=[(i,i*10,'A','B',2.,1.,4.,2.) for i in range(1,5)]+[(5,50,'A','B',float('nan'),1.,4.,2.),(6,60,'A','B',1.,1.,1.,1.)]; assert rolling(_g2)=={}
assert rolling([(i,10,'A','B',2.,1.,4.,2.) for i in range(1,7)])=={}
print("checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
Q="""SELECT f.fixture_id,f.league_id,f.season,f.kickoff,f.home,f.away,s.is_home,
 CASE WHEN s.raw->>'Total Shots' IS NULL THEN NULL ELSE coalesce((s.raw->>'Offsides')::float,0) END off,
 CASE WHEN s.raw->>'Total Shots' IS NULL THEN NULL ELSE coalesce((s.raw->>'Goalkeeper Saves')::float,0) END sav
 FROM af_fixtures f JOIN af_stats s USING(fixture_id) WHERE f.status='FT' AND f.hg IS NOT NULL AND f.season IN (2023,2024,2025)"""
S=pd.read_sql(Q,con); print("stat rows",len(S),S.groupby('season').size().to_dict(),"rows without shots",int(S.off.isna().sum()),flush=True)
Sh=S[S.is_home==True]; Sa=S[S.is_home==False]
M=Sh.merge(Sa[['fixture_id','off','sav']],on='fixture_id',suffixes=('_h','_a')).drop_duplicates('fixture_id')
M['tt']=secs(M.kickoff); R={}
for (l,s),g in M.sort_values('tt').groupby(['league_id','season']):
    R.update(rolling([tuple(x) for x in g[['fixture_id','tt','home','away','off_h','off_a','sav_h','sav_a']].itertuples(index=False)]))
print("games with five earlier games each side",len(R),flush=True)
ST=pd.DataFrame.from_dict(R,orient='index',columns=['OFF','SAVE','bu_h','bu_a']); ST.index.name='fixture_id'; ST=ST.reset_index().merge(M[['fixture_id','season']],on='fixture_id')
B3=ST[ST.season==2023]
CUT={c:(B3[c].quantile(.2),B3[c].quantile(.8)) for c in ('OFF','SAVE')}
BUSY=float(pd.concat([B3.bu_h,B3.bu_a]).quantile(.8))
print("season 2023 games",len(B3),"cuts (20th, 80th)",{k:(round(a,3),round(b,3)) for k,(a,b) in CUT.items()},"BUSY 80th",round(BUSY,3),flush=True)
assert all(a<b for a,b in CUT.values()) and BUSY>0 and len(B3)>1000
G=pd.read_sql("SELECT m.event_id,f.fixture_id,f.season,f.kickoff,f.hg,f.ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL AND f.season IN (2024,2025)",con)
G=G[G.fixture_id.isin(R)]
NMS=pd.read_sql("SELECT DISTINCT ON (event_id) event_id,event_name FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt='MO'",con,params=(list(G.event_id),))
BAD=NMS.event_name.str.contains(r"U-?(?:1[5-9]|2[0-3])\b|\(W\)|\bWomen\b| II\b| B(?: v |$)| Reserves?(?: v |$)|^Jong | v Jong ",regex=True); bad=set(NMS.event_id[BAD]); print('maps naming a youth, women or reserve game, dropped',len(bad),flush=True); G=G[~G.event_id.isin(bad)]
EV=pd.read_sql("SELECT fixture_id,min(coalesce(minute,0)) gm FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal') AND coalesce(minute,0)<=2 GROUP BY 1",con,params=(list(map(int,G.fixture_id)),))
fg=dict(zip(EV.fixture_id,EV.gm)); parts=[]
for i in range(0,len(G),1000):
    P=pd.read_sql("SELECT event_id,mkt,sel,minute,m,ltp::float8 ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND ((mkt='MO' AND sel IN ('HOME','AWAY','DRAW')) OR (mkt='OU25' AND sel IN ('OVER','UNDER'))) AND minute>=0 AND minute<=2 AND ltp>=1.01 AND ltp<1000",con,params=(list(G.event_id.iloc[i:i+1000]),))
    parts.append(P.sort_values(['event_id','mkt','sel','minute','m']).drop_duplicates(['event_id','mkt','sel']))
con.close(); P=pd.concat(parts,ignore_index=True).merge(G[['event_id','fixture_id','kickoff']],on='event_id')
lag=(pd.to_datetime(P.m,utc=True)-pd.to_datetime(P.kickoff,utc=True))/pd.Timedelta(minutes=1); gm=P.fixture_id.map(fg)
bad=(lag<-5)|(lag>20)|(gm.notna()&(gm<P.minute)); print(f"rows dropped by the guards {int(bad.sum())} of {len(P)}",flush=True); P=P[~bad]
P['k']=P.mkt+'_'+P.sel
W=P.pivot_table(index='event_id',columns='k',values='ltp',aggfunc='first').reset_index()
D=G.merge(W,on='event_id').sort_values('kickoff').drop_duplicates('fixture_id').merge(ST.drop(columns=['season']),on='fixture_id')
D['off_t']=secs(D.kickoff); md=float(np.median(D.off_t)); D['tot']=D.hg+D.ag
print("games",len(D),D.season.value_counts().to_dict(),flush=True)
out=[]
def add(nm,x,pc,won):
    x=x[x[pc].notna()]; w=won(x).astype(bool).values; pr=x[pc].values
    for side,f in (('back',bk),('lay',ly)):
        v=np.array([np.nan if (q:=f(float(p),bool(y))) is None else q for p,y in zip(pr,w)],dtype=float); m=np.isfinite(v)
        if m.sum()<30: out.append(dict(line=nm+' '+side,n=int(m.sum()),PASS=False)); continue
        l=line(v[m],np.where(x.off_t.values[m]<md,1,2)); out.append(dict(line=nm+' '+side,n=l['n'],per10=l['per10'],t=l['t'],h1=l['h1'],h2=l['h2'],maxwin=l['maxwin'],won=w[m].mean(),imp=(1/pr[m]).mean(),PASS=l['PASS'] and 'CONTROL' not in nm))
OV=lambda x:x.tot>2.5; UN=lambda x:x.tot<2.5; DR=lambda x:x.hg==x.ag
for c,(a,b) in CUT.items():
    for lab,mask in (('HIGH',D[c]>=b),('LOW',D[c]<=a)):
        x=D[mask]; print(c,lab,len(x),flush=True); add(f'{c} {lab} Over',x,'OU25_OVER',OV); add(f'{c} {lab} Under',x,'OU25_UNDER',UN); add(f'{c} {lab} Draw',x,'MO_DRAW',DR)
for lab,pc,o in (('Over','OU25_OVER',OV),('Under','OU25_UNDER',UN),('Draw','MO_DRAW',DR)): add(f'CONTROL all {lab}',D,pc,o)
rows=[]
for r in D.itertuples():
    for pc,bu,won in (('MO_HOME',r.bu_h,r.hg>r.ag),('MO_AWAY',r.bu_a,r.ag>r.hg)):
        p=getattr(r,pc)
        if p==p: rows.append((r.off_t,p,bu,won))
X=pd.DataFrame(rows,columns='off_t p bu won'.split())
add('BUSY side <2',X[(X.bu>=BUSY)&(X.p<2.0)],'p',lambda x:x.won); add('CONTROL side <2',X[X.p<2.0],'p',lambda x:x.won)
L=pd.DataFrame(out); print(f"\nlines {len(L)}, scored {int((~L.line.str.startswith('CONTROL')).sum())}, at n>=300 {int((L.n>=300).sum())}, {time.time()-T0:.0f}s"); print(L.sort_values('t',ascending=False).round(3).to_string(index=False))
S_=L[L.PASS==True]
print(f"\n== SURVIVORS: {len(S_)}\n",S_.round(3).to_string(index=False) if len(S_) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
