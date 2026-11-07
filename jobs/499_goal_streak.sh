#!/bin/bash
set -o pipefail
# 499_goal_streak (Finder 2026-11-07, queue item 337, Finder's own, source c; entry from jobs/499_table_v_price.sh): the goals streak stat sites quote against the first in-play price. Rule pushed in the queue before any price. Read only, no tables written. LTP only, so a pass is an upper bound.
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
def states(games):
    """games: time-ordered (fid,secs,home,away,hg,ag), one league-season. fid->dict of states from each team's last 5 earlier games; same-time games are not history for each other."""
    H=defaultdict(lambda:deque(maxlen=5)); out={}; i=0
    while i<len(games):
        j=i
        while j<len(games) and games[j][1]==games[i][1]: j+=1
        for f,t,h,a,hg,ag in games[i:j]:
            if len(H[h])==5 and len(H[a])==5:
                x=list(H[h]); y=list(H[a])
                ox=sum(z[0] for z in x); oy=sum(z[0] for z in y); bx=sum(z[1] for z in x); by=sum(z[1] for z in y)
                out[f]=dict(O45=ox>=4 and oy>=4,U15=ox<=1 and oy<=1,BY=bx>=4 and by>=4,BN=bx<=1 and by<=1,
                    NG3_H=all(z[2]==0 for z in x[-3:]),NG3_A=all(z[2]==0 for z in y[-3:]),CS3_H=all(z[3]==0 for z in x[-3:]),CS3_A=all(z[3]==0 for z in y[-3:]))
        for f,t,h,a,hg,ag in games[i:j]:
            o=hg+ag>2.5; b=hg>0 and ag>0
            H[h].append((o,b,hg,ag)); H[a].append((o,b,ag,hg))
        i=j
    return out
# hand-worked: five 2-1 home wins for A over B: over 5 of 5 both, BTTS 5 of 5 both, nobody scoreless, no clean sheet
_o=states([(i,i*10,'A','B',2,1) for i in range(1,6)]+[(6,60,'A','B',0,0)]); assert list(_o)==[6]; _s=_o[6]
assert _s['O45'] and _s['BY'] and not _s['U15'] and not _s['BN'] and not _s['NG3_H'] and not _s['CS3_A']
# five 1-0 wins for A over B: Over none, BTTS none; B failed to score in 3 (away side here), A clean sheets in 3
_o=states([(i,i*10,'A','B',1,0) for i in range(1,6)]+[(6,60,'A','B',0,0)]); _s=_o[6]
assert _s['U15'] and _s['BN'] and not _s['O45'] and not _s['BY'] and _s['NG3_A'] and not _s['NG3_H'] and _s['CS3_H'] and not _s['CS3_A']
# NG3 reads the last three only: scored in game 2, not in games 3, 4, 5. The team is read from its own side when it was away.
_o=states([(1,10,'A','B',1,1),(2,20,'B','A',0,2),(3,30,'A','B',0,1),(4,40,'B','A',1,0),(5,50,'A','B',0,3),(6,60,'A','B',0,0)]); assert _o[6]['NG3_H'] and not _o[6]['NG3_A']
assert states([(i,10,'A','B',1,0) for i in range(1,7)])=={}   # same kick-off time is not history
print("checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
F=pd.read_sql("SELECT fixture_id,league_id,season,kickoff,home,away,hg,ag FROM af_fixtures WHERE status='FT' AND hg IS NOT NULL AND ag IS NOT NULL AND season IN (2024,2025)",con)
F['tt']=secs(F.kickoff); R={}
for (l,s),g in F.sort_values('tt').groupby(['league_id','season']):
    R.update(states([tuple(x) for x in g[['fixture_id','tt','home','away','hg','ag']].itertuples(index=False)]))
print("fixtures",len(F),"with five earlier games each side",len(R),flush=True)
G=pd.read_sql("SELECT m.event_id,f.fixture_id,f.kickoff,f.hg,f.ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL AND f.ag IS NOT NULL AND f.season IN (2024,2025)",con)
G=G[G.fixture_id.isin(R)]
NMS=pd.read_sql("SELECT DISTINCT ON (event_id) event_id,event_name FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt='MO'",con,params=(list(G.event_id),))
BAD=NMS.event_name.str.contains(r"U-?(?:1[5-9]|2[0-3])\b|\(W\)|\bWomen\b| II\b| B(?: v |$)| Reserves?(?: v |$)|^Jong | v Jong ",regex=True); bad=set(NMS.event_id[BAD]); print('maps naming a youth, women or reserve game, dropped',len(bad),flush=True); G=G[~G.event_id.isin(bad)]
EV=pd.read_sql("SELECT fixture_id,min(coalesce(minute,0)) gm FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal') AND coalesce(minute,0)<=2 GROUP BY 1",con,params=(list(map(int,G.fixture_id)),))
fg=dict(zip(EV.fixture_id,EV.gm)); parts=[]
for i in range(0,len(G),1000):
    P=pd.read_sql("SELECT event_id,mkt,sel,minute,m,ltp::float8 ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND ((mkt='MO' AND sel IN ('HOME','AWAY')) OR (mkt='OU25' AND sel IN ('OVER','UNDER')) OR (mkt='BTTS' AND sel IN ('YES','NO'))) AND minute>=0 AND minute<=2 AND ltp>=1.01 AND ltp<1000",con,params=(list(G.event_id.iloc[i:i+1000]),))
    parts.append(P.sort_values(['event_id','mkt','sel','minute','m']).drop_duplicates(['event_id','mkt','sel']))
con.close(); P=pd.concat(parts,ignore_index=True).merge(G[['event_id','fixture_id','kickoff']],on='event_id')
lag=(pd.to_datetime(P.m,utc=True)-pd.to_datetime(P.kickoff,utc=True))/pd.Timedelta(minutes=1); gm=P.fixture_id.map(fg)
bad=(lag<-5)|(lag>20)|(gm.notna()&(gm<P.minute)); print(f"rows dropped by the guards {int(bad.sum())} of {len(P)}",flush=True); P=P[~bad]
P['k']=P.mkt+'_'+P.sel
W=P.pivot_table(index='event_id',columns='k',values='ltp',aggfunc='first').reset_index()
D=G.merge(W,on='event_id').sort_values('kickoff').drop_duplicates('fixture_id'); D['off']=secs(D.kickoff); md=float(np.median(D.off)); D['tot']=D.hg+D.ag; D['bt']=(D.hg>0)&(D.ag>0)
for c in ('O45','U15','BY','BN','NG3_H','NG3_A','CS3_H','CS3_A'): D[c]=[R[f][c] for f in D.fixture_id]
print("games",len(D),"states",{c:int(D[c].sum()) for c in ('O45','U15','BY','BN','NG3_H','NG3_A','CS3_H','CS3_A')},flush=True)
out=[]; ctrl={}
def add(nm,x,pc,won,key=None,base=False):
    x=x[x[pc].notna()]; w=np.asarray(won(x),dtype=bool); pr=x[pc].values; key=key or pc
    for side,f in (('back',bk),('lay',ly)):
        v=np.array([np.nan if (q:=f(float(p),bool(y))) is None else q for p,y in zip(pr,w)],dtype=float); m=np.isfinite(v); v2=v[m]
        if base: ctrl[(key,side)]=v2
        l=line(v2,np.where(x.off.values[m]<md,1,2)); nv=ctrl.get((key,side)); dt=np.nan
        if not base and nv is not None and len(v2)>1: dt=(v2.mean()-nv.mean())/np.sqrt(v2.var(ddof=1)/len(v2)+nv.var(ddof=1)/len(nv))
        out.append(dict(line=f'{nm} {pc} {side}',n=l['n'],per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],maxwin=l['maxwin'],won=w[m].mean() if m.any() else np.nan,imp=(1/pr[m]).mean() if m.any() else np.nan,t_v_ctrl=dt,PASS=l['PASS'] and not base))
OV=lambda x:x.tot>2.5; UN=lambda x:x.tot<2.5; BY=lambda x:x.bt; BN=lambda x:~x.bt
for pc,fn,sts in (('OU25_OVER',OV,('O45','U15')),('OU25_UNDER',UN,('O45','U15')),('BTTS_YES',BY,('BY','BN')),('BTTS_NO',BN,('BY','BN'))):
    add('CONTROL all',D,pc,fn,base=True)
    for st in sts: add(st,D[D[st]],pc,fn)
rows=[]
for r in D.itertuples():
    for s,pc,ng,cs,won in (('H','MO_HOME',r.NG3_H,r.CS3_H,r.hg>r.ag),('A','MO_AWAY',r.NG3_A,r.CS3_A,r.ag>r.hg)):
        p=getattr(r,pc)
        if p==p: rows.append((r.off,s,p,ng,cs,won))
X=pd.DataFrame(rows,columns='off s p ng cs won'.split())
add('CONTROL side',X,'p',lambda x:x.won,key='team',base=True); add('NG3 team',X[X.ng],'p',lambda x:x.won,key='team'); add('CS3 team',X[X.cs],'p',lambda x:x.won,key='team')
L=pd.DataFrame(out); print(f"\nlines {len(L)}, scored {int((~L.line.str.startswith('CONTROL')).sum())}, at n>=300 {int((L.n>=300).sum())}, {time.time()-T0:.0f}s"); print(L.sort_values('t',ascending=False).round(3).drop(columns=['n1','n2']).to_string(index=False))
S_=L[L.PASS==True]
print(f"\n== SURVIVORS: {len(S_)}\n",S_.round(3).to_string(index=False) if len(S_) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
