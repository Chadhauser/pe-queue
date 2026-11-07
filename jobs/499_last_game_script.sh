#!/bin/bash
set -o pipefail
# 499_last_game_script (Finder 2026-11-07, queue items 345 and 347, Finder's own, source d; entry from jobs/499_goal_streak.sh): how a side's last game went, and a run of home or away games, against the first in-play price. Rules pushed in the queue before any price. Read only, no tables written. LTP only, so a pass is an upper bound.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(1_800_000_000,1_800_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import defaultdict
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line
from lib_official import bk,ly,secs,checks
import lib_cand; lib_cand._checks(); checks()
pd.set_option('display.width',230); pd.set_option('display.max_rows',80); pd.set_option('display.max_columns',30)
T0=time.time()
def states(games):
    """games: time-ordered (fid,secs,home,away,hg,ag,hth,hta), one league-season, ht may be nan. fid->dict. Same-time games are not history for each other."""
    last={}; run={}; out={}; i=0
    while i<len(games):
        j=i
        while j<len(games) and games[j][1]==games[i][1]: j+=1
        for f,t,h,a,hg,ag,hh,ha in games[i:j]:
            rh=run.get(h); ra=run.get(a)
            hrun=rh[1]+1 if rh and rh[0]=='H' else 1 if rh else 0
            arun=ra[1]+1 if ra and ra[0]=='A' else 1 if ra else 0
            out[f]=dict(BLEW_H=last.get(h)=='BLEW',BLEW_A=last.get(a)=='BLEW',RALLY_H=last.get(h)=='RALLY',RALLY_A=last.get(a)=='RALLY',H2=hrun>=2,H3=hrun>=3,A2=arun>=2,A3=arun>=3)
        for f,t,h,a,hg,ag,hh,ha in games[i:j]:
            for tm,me,op,mh,oh,place in ((h,hg,ag,hh,ha,'H'),(a,ag,hg,ha,hh,'A')):
                r=run.get(tm); run[tm]=(place,r[1]+1) if r and r[0]==place else (place,1)
                if mh==mh and oh==oh:
                    last[tm]='BLEW' if mh>oh and me<=op else 'RALLY' if mh<oh and me>op else 'OTHER'
                else: last[tm]=None
        i=j
    return out
_n=float('nan')
# hand-worked: A leads B 1-0 at half-time, ends 1-1: A BLEW. B then away again at A. B's second away in a row, A's second home in a row.
_o=states([(1,10,'A','B',1,1,1,0),(2,20,'A','B',0,0,0,0)])
assert _o[1]=={'BLEW_H':False,'BLEW_A':False,'RALLY_H':False,'RALLY_A':False,'H2':False,'H3':False,'A2':False,'A3':False}
assert _o[2]['BLEW_H'] and not _o[2]['BLEW_A'] and not _o[2]['RALLY_A'] and _o[2]['H2'] and _o[2]['A2'] and not _o[2]['H3']
# A trails at half-time 0-1, wins 2-1: RALLY for A, and B (led and lost) BLEW. Third home in a row reads H3.
_o=states([(1,10,'A','B',2,1,0,1),(2,20,'A','C',0,0,0,0),(3,30,'A','B',0,0,0,0)])
assert _o[2]['RALLY_H'] and not _o[2]['BLEW_H'] and _o[3]['BLEW_A'] and _o[3]['H3'] and _o[2]['H2'] and not _o[2]['H3'] and not _o[2]['A2']
# a home game breaks an away run; led at half-time and won is neither; missing half-time carries no state
_o=states([(1,10,'A','B',1,0,1,0),(2,20,'B','A',0,0,_n,_n),(3,30,'A','B',0,0,0,0)])
assert not _o[3]['A2'] and not _o[3]['H2'] and not _o[2]['BLEW_A'] and not _o[3]['BLEW_H'] and not _o[3]['RALLY_A']
# same kick-off time is not history
_o=states([(1,10,'A','B',1,1,1,0),(2,10,'A','B',0,0,0,0)]); assert not _o[2]['BLEW_H'] and not _o[2]['H2']
print("checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
F=pd.read_sql("SELECT fixture_id,league_id,season,kickoff,home,away,hg,ag,ht_hg::float8 hh,ht_ag::float8 ha FROM af_fixtures WHERE status='FT' AND hg IS NOT NULL AND ag IS NOT NULL AND season IN (2024,2025)",con)
F['tt']=secs(F.kickoff); R={}
for (l,s),g in F.sort_values('tt').groupby(['league_id','season']):
    R.update(states([tuple(x) for x in g[['fixture_id','tt','home','away','hg','ag','hh','ha']].itertuples(index=False)]))
print("fixtures",len(F),"half-time scores missing",int(F.hh.isna().sum()),flush=True)
G=pd.read_sql("SELECT m.event_id,f.fixture_id,f.kickoff,f.hg,f.ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL AND f.ag IS NOT NULL AND f.season IN (2024,2025)",con)
G=G[G.fixture_id.isin(R)]
NMS=pd.read_sql("SELECT DISTINCT ON (event_id) event_id,event_name FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt='MO'",con,params=(list(G.event_id),))
BAD=NMS.event_name.str.contains(r"U-?(?:1[5-9]|2[0-3])\b|\(W\)|\bWomen\b| II\b| B(?: v |$)| Reserves?(?: v |$)|^Jong | v Jong ",regex=True); bad=set(NMS.event_id[BAD]); print('maps naming a youth, women or reserve game, dropped',len(bad),flush=True); G=G[~G.event_id.isin(bad)]
EV=pd.read_sql("SELECT fixture_id,min(coalesce(minute,0)) gm FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal') AND coalesce(minute,0)<=2 GROUP BY 1",con,params=(list(map(int,G.fixture_id)),))
fg=dict(zip(EV.fixture_id,EV.gm)); parts=[]
for i in range(0,len(G),1000):
    P=pd.read_sql("SELECT event_id,mkt,sel,minute,m,ltp::float8 ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt='MO' AND sel IN ('HOME','AWAY') AND minute>=0 AND minute<=2 AND ltp>=1.01 AND ltp<1000",con,params=(list(G.event_id.iloc[i:i+1000]),))
    parts.append(P.sort_values(['event_id','mkt','sel','minute','m']).drop_duplicates(['event_id','mkt','sel']))
con.close(); P=pd.concat(parts,ignore_index=True).merge(G[['event_id','fixture_id','kickoff']],on='event_id')
lag=(pd.to_datetime(P.m,utc=True)-pd.to_datetime(P.kickoff,utc=True))/pd.Timedelta(minutes=1); gm=P.fixture_id.map(fg)
bad=(lag<-5)|(lag>20)|(gm.notna()&(gm<P.minute)); print(f"rows dropped by the guards {int(bad.sum())} of {len(P)}",flush=True); P=P[~bad]
P['k']=P.mkt+'_'+P.sel
W=P.pivot_table(index='event_id',columns='k',values='ltp',aggfunc='first').reset_index()
D=G.merge(W,on='event_id').sort_values('kickoff').drop_duplicates('fixture_id'); D['off']=secs(D.kickoff); md=float(np.median(D.off))
rows=[]
for r in D.itertuples():
    st=R[r.fixture_id]
    for s,p,won,mine in (('H',r.MO_HOME,r.hg>r.ag,('H2','H3')),('A',r.MO_AWAY,r.ag>r.hg,('A2','A3'))):
        if p==p: rows.append(dict(eid=r.event_id,off=r.off,s=s,p=p,won=won,BLEW=st['BLEW_'+s],RALLY=st['RALLY_'+s],R2=st[mine[0]],R3=st[mine[1]],BOTH=st['H2'] and st['A2']))
X=pd.DataFrame(rows); print("games",len(D),"sides",len(X),{c:int(X[c].sum()) for c in ('BLEW','RALLY','R2','R3','BOTH')},flush=True)
out=[]
def add(item,nm,x):
    w=x.won.astype(bool).values; pr=x.p.values
    for side,f in (('back',bk),('lay',ly)):
        v=np.array([np.nan if (q:=f(float(a),bool(y))) is None else q for a,y in zip(pr,w)],dtype=float); m=np.isfinite(v)
        if m.sum()<30: out.append(dict(item=item,line=nm+' '+side,n=int(m.sum()),PASS=False)); continue
        l=line(v[m],np.where(x.off.values[m]<md,1,2)); out.append(dict(item=item,line=nm+' '+side,n=l['n'],per10=l['per10'],t=l['t'],h1=l['h1'],h2=l['h2'],maxwin=l['maxwin'],won=w[m].mean(),imp=(1/pr[m]).mean(),games=x.eid.iloc[np.where(m)[0]].nunique(),PASS=l['PASS'] and 'CONTROL' not in nm))
BANDS=(('all',X.p>0),('<2.0',X.p<2.0),('2.2+',X.p>=2.2))
for b,mk in BANDS:
    add('345',f'CONTROL side {b}',X[mk])
    for c in ('BLEW','RALLY'): add('345',f'{c} {b}',X[mk&X[c]])
H=X[X.s=='H']; A=X[X.s=='A']
add('347','CONTROL home',H); add('347','CONTROL away',A)
add('347','H2 home',H[H.R2]); add('347','H3 home',H[H.R3]); add('347','A2 away',A[A.R2]); add('347','A3 away',A[A.R3]); add('347','BOTH home',H[H.BOTH]); add('347','BOTH away',A[A.BOTH])
L=pd.DataFrame(out); print(f"\nlines {len(L)}, scored {int((~L.line.str.contains('CONTROL')).sum())}, at n>=300 {int((L.n>=300).sum())}, {time.time()-T0:.0f}s"); print(L.sort_values('t',ascending=False).round(3).to_string(index=False))
S_=L[L.PASS==True]
print(f"\n== SURVIVORS: {len(S_)}\n",S_.round(3).to_string(index=False) if len(S_) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
