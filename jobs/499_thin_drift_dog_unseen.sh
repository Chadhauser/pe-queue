#!/bin/bash
set -o pipefail
# 499_thin_drift_dog_unseen (Finder 2026-11-05, queue item 160, Finder's own, source a; from jobs/499_longtail_move.sh, settle and fills as jobs/499_thin_long_dog.sh): lay an underdog that has drifted in a thin senior game, on games without official results. Rule pushed in the queue before these prices were read. Read only.
# MO, senior, thin: MO prints T-60 to T-20 at or under 6. Dog: longer team at the entry print. Early: last real print T-180 to T-60, never forward-filled; no early print not traded, counted. Entry: last print T-20 to T-2. Scored: entry print / early at or over 1.10, lay at the worse of the entry print and the next within 120 s, one tick adverse, 2%, £10 liability. Over 50 not traded. One bet per event on the lowest id. Events not in bf_hist_result. Settled on the last goal_timeline row at minute 88+. Prints only: an upper bound.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import norm,jac,loose,line
from lib_official import group,ly,fill,last_in,secs,checks
import lib_cand; lib_cand._checks(); checks()
def mo_pair(home,away,runners):
    """As jobs/499_longtail_senior.sh."""
    r=[x for x in runners if str(x).strip().lower()!='the draw']
    if len(r)!=2: return None
    H,A,a,b=norm(home),norm(away),norm(r[0]),norm(r[1])
    s1,s2=jac(a,H)+jac(b,A),jac(a,A)+jac(b,H)
    if s1==s2: return None
    x,y=(r[0],r[1]) if s1>s2 else (r[1],r[0])
    if not (norm(x)&H and norm(y)&A): return None
    return x,y
def drifted(entry,early): return entry/early>=1.10
# known answers: the edge of the band, and the lay at a thin dog price (fill 6.0 -> 6.2, stake 10/5.2, wins 1.885 after 2%, loses 10)
assert drifted(5.5,5.0) and not drifted(5.4,5.0) and not drifted(5.0,5.0) and not drifted(4.0,5.0)
assert abs(ly(6.0,False)-10/5.2*.98)<1e-9 and ly(6.0,True)==-10.0
print("checks: OK",flush=True); T0=time.time()
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
HAS=set(pd.read_sql("SELECT DISTINCT event_id FROM bf_hist_result WHERE sport='Soccer' AND market_type='MATCH_ODDS'",con).event_id)
X=pd.read_sql("SELECT market_id,event_id,event_name ev,market_time mt,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type='MATCH_ODDS' AND market_time>='2026-05-01' AND market_time<'2026-10-02' AND NOT inplay AND ltp>=1.01 AND ltp<1000 AND ts>=market_time-interval '180 minutes'",con)
GT=pd.read_sql("SELECT DISTINCT ON (fixture_id) fixture_id,home_team,away_team,captured_at,minute,score_home,score_away,status FROM goal_timeline WHERE captured_at>='2026-05-01' AND captured_at<'2026-10-03' AND score_home IS NOT NULL AND score_away IS NOT NULL ORDER BY fixture_id,captured_at DESC",con); con.close()
GT['t']=secs(GT.captured_at); GT['mn']=pd.to_numeric(GT.minute,errors='coerce')
GT=GT[(GT.mn>=88)&~GT.status.isin(['AET','PEN','ET'])].sort_values('t').reset_index(drop=True); GT['H']=GT.home_team.map(norm); GT['A']=GT.away_team.map(norm); tt=GT.t.values
X['tt']=secs(X.ts); X['off']=secs(X.mt); X=X.sort_values('tt',kind='stable')
ids=X.drop_duplicates('market_id')[['market_id','event_id']]; keep=ids.sort_values('market_id').drop_duplicates('event_id').market_id
X=X[X.market_id.isin(set(keep))&~X.event_id.isin(HAS)].drop_duplicates(['market_id','sel','tt'])
print(f"unseen MO events {X.event_id.nunique()}, finished goal_timeline rows {len(GT)}, {time.time()-T0:.0f}s",flush=True)
C=Counter(); rows=[]
for e,g in X.groupby('event_id'):
    ev=g.ev.iloc[0]; o=float(g.off.iloc[0])
    if group(ev) is not None: C['women or youth']+=1; continue
    hm,_x,aw=ev.partition(' v '); pr=mo_pair(hm,aw,list(g.sel.unique()))
    if pr is None: C['runners not matched']+=1; continue
    if int(((g.tt>=o-3600)&(g.tt<o-1200)).sum())>6: C['not thin']+=1; continue
    ent={}
    for s in pr:
        y=g[g.sel==s]; ts,px=y.tt.values,y.ltp.values; i=last_in(ts,o-1200,o-120)
        if i is not None: ent[s]=(ts,px,i)
    if len(ent)<2: C['no print on both teams']+=1; continue
    hf=ent[pr[0]][1][ent[pr[0]][2]]<=ent[pr[1]][1][ent[pr[1]][2]]; dog=pr[1] if hf else pr[0]; dh=not hf
    ts,px,i=ent[dog]; j=last_in(ts,o-10800,o-3600)
    if j is None: C['no early print']+=1; continue
    if not drifted(float(px[i]),float(px[j])): C['not drifted']+=1; continue
    p=fill(ts,px,i,'L')
    if p>50: C['over 50']+=1; continue
    lo,hi=np.searchsorted(tt,o),np.searchsorted(tt,o+14400); fx=loose(norm(hm),norm(aw),[(z.H,z.A,z.Index) for z in GT.iloc[lo:hi].itertuples()])
    if fx is None: C['no score match, dropped']+=1; continue
    sh,sa=int(GT.score_home[fx]),int(GT.score_away[fx]); won=sh>sa if dh else sa>sh
    rows.append((e,o,won,1/p,ly(p,won)))
print("counted:",dict(sorted(C.items())),flush=True)
R=pd.DataFrame(rows,columns='e off won imp v'.split()); assert R.e.is_unique; md=np.median(R.off.values); R['h']=np.where(R.off<md,1,2); print("by month:",pd.to_datetime(R.off,unit='s').dt.strftime('%Y-%m').value_counts().sort_index().to_dict(),flush=True)
l=line(R.v.values,R.h.values); O=pd.DataFrame([dict(line="THIN DOG DRIFT lay (scored)",n=l['n'],games=R.e.nunique(),per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],won=R.won.mean(),imp=R.imp.mean(),PASS=l['PASS'])])
pd.set_option('display.width',200); print("\n"+O.round(3).to_string(index=False))
S=O[O.PASS]; print(f"\n== SURVIVORS: {len(S)} of 1\n",S.round(3).to_string(index=False) if len(S) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
