#!/bin/bash
set -o pipefail
# 499_ou35_under_mid (Finder 2026-11-05, queue item 150, Finder's own, source c; from jobs/499_longtail_senior.sh): lay Under 3.5 in a mid-liquidity senior game, on games with no official result. Rule pushed in the queue before any of these prices was read. Read only.
# ENTRY as item 144: last non-in-play Under 3.5 print T-20 to T-2, worse of it and the next print within 120 s, one tick adverse, 2%, £10 risk, hold to the result. Over 50 not traded. SENIOR: lib_official.group is None. MID: MO prints T-60 to T-20 in 7 to 14, the cuts 6 and 14 from item 144, counted on one MO id per event as the tape holds Sep MO twice.
# SETTLE on goal_timeline finished rows as jobs/499_lay_over25_all.sh; no score match dropped, counted. h1/h2 by date median. Control: the same lay in the other senior games.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import norm,loose,line
from lib_official import group,ly,fill,last_in,secs,checks
import lib_cand; lib_cand._checks(); checks()
def band(n): return 'MID' if 7<=n<=14 else 'OTHER'
assert band(6)=='OTHER' and band(7)=='MID' and band(14)=='MID' and band(15)=='OTHER'
def under_won(h,a): return h+a<3.5
assert under_won(2,1) and under_won(3,0) and not under_won(2,2) and not under_won(4,0)
print("checks: OK",flush=True); T0=time.time()
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
HAS=set(pd.read_sql("SELECT DISTINCT event_id FROM bf_hist_result WHERE sport='Soccer' AND market_type='OVER_UNDER_35'",con).event_id)
X=pd.read_sql("SELECT market_id,event_id,event_name ev,market_time mt,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type='OVER_UNDER_35' AND market_time>='2026-05-01' AND market_time<'2026-10-02' AND NOT inplay AND ltp>=1.01 AND ltp<1000 AND sel ILIKE 'under%%'",con)
M=pd.read_sql("SELECT market_id,event_id,sel,ts,market_time mt FROM bf_hist_other WHERE sport='Soccer' AND market_type='MATCH_ODDS' AND market_time>='2026-05-01' AND market_time<'2026-10-02' AND NOT inplay AND ltp>=1.01 AND ltp<1000 AND ts>=market_time-interval '60 minutes' AND ts<market_time-interval '20 minutes'",con)
GT=pd.read_sql("SELECT DISTINCT ON (fixture_id) fixture_id,home_team,away_team,captured_at,minute,score_home,score_away,status FROM goal_timeline WHERE captured_at>='2026-05-01' AND captured_at<'2026-10-03' AND score_home IS NOT NULL AND score_away IS NOT NULL ORDER BY fixture_id,captured_at DESC",con); con.close()
GT['t']=secs(GT.captured_at); GT['mn']=pd.to_numeric(GT.minute,errors='coerce')
GT=GT[GT.status.isin(['FT','Match Finished','FINISHED'])|((GT.mn>=88)&~GT.status.isin(['AET','PEN','ET']))].sort_values('t').reset_index(drop=True); GT['H']=GT.home_team.map(norm); GT['A']=GT.away_team.map(norm); tt=GT.t.values
keepM=M.drop_duplicates('market_id')[['market_id','event_id']].sort_values('market_id').drop_duplicates('event_id').market_id
M=M[M.market_id.isin(set(keepM))].drop_duplicates(['market_id','sel','ts']); LQ=M.groupby('event_id').size().to_dict()
X['tt']=secs(X.ts); X['off']=secs(X.mt); X=X[~X.event_id.isin(HAS)].sort_values('tt',kind='stable')
keep=X.drop_duplicates('market_id')[['market_id','event_id']].sort_values('market_id').drop_duplicates('event_id').market_id
X=X[X.market_id.isin(set(keep))].drop_duplicates(['market_id','tt'])
print(f"unseen events with Under 3.5 prints {X.event_id.nunique()}, excluded with results {len(HAS)}, {time.time()-T0:.0f}s",flush=True)
C=Counter(); rows=[]
for e,g in X.groupby('event_id'):
    ev=g.ev.iloc[0]
    if group(ev) is not None: C['women or youth']+=1; continue
    o=float(g.off.iloc[0]); ts,px=g.tt.values,g.ltp.values; i=last_in(ts,o-1200,o-120)
    if i is None: C['no print in window']+=1; continue
    h,_x,a=ev.partition(' v '); lo,hi=np.searchsorted(tt,o),np.searchsorted(tt,o+14400); fx=loose(norm(h),norm(a),[(x.H,x.A,x.Index) for x in GT.iloc[lo:hi].itertuples()])
    if fx is None: C['no score match, dropped']+=1; continue
    p=fill(ts,px,i,'L')
    if p>50: C['over 50']+=1; continue
    won=under_won(int(GT.score_home[fx]),int(GT.score_away[fx]))
    rows.append((e,o,band(LQ.get(e,0)),won,1/p,ly(p,won)))
print("counted:",dict(sorted(C.items())),flush=True)
R=pd.DataFrame(rows,columns='e off b won imp v'.split()); md=np.median(R.off.values); R['h']=np.where(R.off<md,1,2)
print("trades by month:",pd.to_datetime(R.off,unit='s').dt.strftime('%Y-%m').value_counts().sort_index().to_dict(),"median",pd.to_datetime(md,unit='s'))
out=[]
for k,x in R.groupby('b'):
    l=line(x.v.values,x.h.values); out.append(dict(line=f"{k} OU35 Under lay",n=l['n'],games=x.e.nunique(),per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],won=x.won.mean(),imp=x.imp.mean(),PASS=l['PASS']))
O=pd.DataFrame(out); pd.set_option('display.width',200); print("\n"+O.round(3).to_string(index=False))
S=O[O.PASS&O.line.str.startswith('MID')]; print(f"\n== SURVIVORS: {len(S)} of 1\n",S.round(3).to_string(index=False) if len(S) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
