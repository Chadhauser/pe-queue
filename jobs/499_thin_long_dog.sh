#!/bin/bash
set -o pipefail
# 499_thin_long_dog (Finder 2026-11-05, queue item 154, Finder's own, source c; from jobs/499_thin_dog_lay_unseen.sh): lay the long underdog in a thin senior game. Rule pushed in the queue before any price by band was read. Read only.
# As item 153 in every respect: last MO print T-20 to T-2 on each team, worse of print and next within 120 s, one tick adverse, 2%, £10 liability, one bet per event on one id, games not in bf_hist_result, settled on the last goal_timeline row at minute 88+. THIN: MO prints T-60 to T-20 at or under 6. LONG: dog fill at or over 5.0, one scored line. Under 5.0 is shown as the complement only.
# Item 153's games, so this is not a fresh sample: only the band was unseen. A pass would earn a test on later months, nothing more.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import norm,jac,loose,line
from lib_official import group,ly,fill,last_in,secs,checks
import lib_cand; lib_cand._checks(); checks()
TYPES=['MATCH_ODDS','OVER_UNDER_15','OVER_UNDER_25','OVER_UNDER_35','BOTH_TEAMS_TO_SCORE','FIRST_HALF_GOALS_05']
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
def band(p): return 'LONG' if p>=5.0 else 'SHORT'
assert band(5.0)=='LONG' and band(4.9)=='SHORT' and band(50)=='LONG' and band(1.5)=='SHORT'
print("checks: OK",flush=True); T0=time.time()
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
HAS=set(pd.read_sql("SELECT DISTINCT event_id FROM bf_hist_result WHERE sport='Soccer' AND market_type=ANY(%s)",con,params=(TYPES,)).event_id)
X=pd.read_sql("SELECT market_id,event_id,event_name ev,market_time mt,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type='MATCH_ODDS' AND market_time>='2026-05-01' AND market_time<'2026-10-02' AND NOT inplay AND ltp>=1.01 AND ltp<1000 AND ts>=market_time-interval '60 minutes'",con)
GT=pd.read_sql("SELECT DISTINCT ON (fixture_id) fixture_id,home_team,away_team,captured_at,minute,score_home,score_away,status FROM goal_timeline WHERE captured_at>='2026-05-01' AND captured_at<'2026-10-03' AND score_home IS NOT NULL AND score_away IS NOT NULL ORDER BY fixture_id,captured_at DESC",con); con.close()
GT['t']=secs(GT.captured_at); GT['mn']=pd.to_numeric(GT.minute,errors='coerce')
GT=GT[(GT.mn>=88)&~GT.status.isin(['AET','PEN','ET'])].sort_values('t').reset_index(drop=True); GT['H']=GT.home_team.map(norm); GT['A']=GT.away_team.map(norm); tt=GT.t.values
X['tt']=secs(X.ts); X['off']=secs(X.mt); X=X.sort_values('tt',kind='stable')
ids=X.drop_duplicates('market_id')[['market_id','event_id']]; keep=ids.sort_values('market_id').drop_duplicates('event_id').market_id
X=X[X.market_id.isin(set(keep))&~X.event_id.isin(HAS)].drop_duplicates(['market_id','sel','tt'])
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
    ts,px,i=ent[dog]; p=fill(ts,px,i,'L')
    if p>50: C['over 50']+=1; continue
    h,_y,a=ev.partition(' v '); lo,hi=np.searchsorted(tt,o),np.searchsorted(tt,o+14400); fx=loose(norm(h),norm(a),[(z.H,z.A,z.Index) for z in GT.iloc[lo:hi].itertuples()])
    if fx is None: C['no score match, dropped']+=1; continue
    sh,sa=int(GT.score_home[fx]),int(GT.score_away[fx]); won=sh>sa if dh else sa>sh
    rows.append((e,o,band(p),won,1/p,ly(p,won)))
print("counted:",dict(sorted(C.items())),flush=True)
R=pd.DataFrame(rows,columns='e off b won imp v'.split()); md=np.median(R.off.values); R['h']=np.where(R.off<md,1,2)
out=[]
for k,x in R.groupby('b'):
    l=line(x.v.values,x.h.values); out.append(dict(line=f"THIN {k} dog lay",n=l['n'],games=x.e.nunique(),per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],won=x.won.mean(),imp=x.imp.mean(),PASS=l['PASS']))
O=pd.DataFrame(out); pd.set_option('display.width',200); print("\n"+O.round(3).to_string(index=False))
S=O[O.PASS&O.line.str.contains('LONG')]; print(f"\n== SURVIVORS: {len(S)} of 1\n",S.round(3).to_string(index=False) if len(S) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
