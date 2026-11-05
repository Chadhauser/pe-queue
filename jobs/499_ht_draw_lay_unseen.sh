#!/bin/bash
set -o pipefail
# 499_ht_draw_lay_unseen (Finder 2026-11-05, queue item 159, Finder's own, source c; from jobs/499_longtail_other_markets.sh): lay the half-time draw before the off, on games without official results. Rule pushed in the queue before these prices were read. Read only.
# HALF_TIME The Draw, all groups, one scored line. Last non-in-play print T-20 to T-2 min, worse of it and the next non-in-play print within 120 s, one tick adverse, 2%, £10 liability. One bet per event on the lowest id. Events not in bf_hist_result. Settled on the last goal_timeline HT row as jobs/499_fh3_older_months.sh; no HT row not traded, counted. Over 50 not traded. Prints only: an upper bound.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import norm,loose,line
from lib_official import group,ly,fill,last_in,secs,checks
import lib_cand; lib_cand._checks(); checks()
def drew(h,a): return h==a
# known answers: draws and not, the lay at a typical HT draw price (fill 2.5 -> 2.52, stake 10/1.52, wins 6.447 after 2%, loses 10)
assert drew(0,0) and drew(1,1) and not drew(1,0) and not drew(0,2)
assert abs(ly(2.5,False)-10/1.52*.98)<1e-9 and ly(2.5,True)==-10.0
print("checks: OK",flush=True); T0=time.time()
pd.set_option('display.width',220); pd.set_option('display.max_columns',30)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
OFF=pd.read_sql("SELECT event_id,market_id,sel,status FROM bf_hist_result WHERE sport='Soccer' AND market_type='HALF_TIME'",con)
HAS=set(pd.read_sql("SELECT DISTINCT event_id FROM bf_hist_result WHERE sport='Soccer'",con).event_id)
OW={e:(g.status[g.sel=='The Draw']=='WINNER').any() for e,g in OFF.groupby('event_id') if (g.status=='WINNER').sum()==1 and (g.sel=='The Draw').any()}
X=pd.read_sql("SELECT market_id,event_id,event_name ev,market_time mt,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type='HALF_TIME' AND sel='The Draw' AND market_time>='2026-05-01' AND market_time<'2026-10-02' AND NOT inplay AND ltp>=1.01 AND ltp<1000 AND ts>=market_time-interval '20 minutes'",con)
HT=pd.read_sql("SELECT DISTINCT ON (fixture_id) fixture_id,home_team,away_team,captured_at,score_home h,score_away a FROM goal_timeline WHERE captured_at>='2026-05-01' AND captured_at<'2026-10-03' AND status='HT' AND score_home IS NOT NULL AND score_away IS NOT NULL ORDER BY fixture_id,captured_at DESC",con); con.close()
print(f"official HT settled {len(OW)}, events with any result {len(HAS)}, goal_timeline HT rows {len(HT)}, HT draw rows {len(X)}, {time.time()-T0:.0f}s",flush=True)
HT['t']=secs(HT.captured_at); HT=HT.sort_values('t').reset_index(drop=True); HT['H']=HT.home_team.map(norm); HT['A']=HT.away_team.map(norm); tt=HT.t.values
X['tt']=secs(X.ts); X['off']=secs(X.mt); X=X.drop_duplicates(['market_id','tt']).sort_values('tt',kind='stable')
ids=X.drop_duplicates('market_id')[['market_id','event_id']]; keep=set(ids.sort_values('market_id').drop_duplicates('event_id').market_id); print(f"HALF_TIME ids {len(ids)}, events {ids.event_id.nunique()}",flush=True)
X=X[X.market_id.isin(keep)]
C=Counter(); rows=[]; chk=Counter()
for e,g in X.groupby('event_id'):
    ev=g.ev.iloc[0]; o=float(g.off.iloc[0]); h,_x,a=ev.partition(' v ')
    lo,hi=np.searchsorted(tt,o),np.searchsorted(tt,o+7200); fx=loose(norm(h),norm(a),[(z.H,z.A,z.Index) for z in HT.iloc[lo:hi].itertuples()])
    d=None if fx is None else drew(int(HT.h[fx]),int(HT.a[fx]))
    if e in OW and d is not None: chk['agree' if d==OW[e] else 'disagree']+=1
    if e in HAS: C['official result held, seen']+=1; continue
    ts,px=g.tt.values,g.ltp.values; i=last_in(ts,o-1200,o-120)
    if i is None: C['no print in window']+=1; continue
    p=fill(ts,px,i,'L')
    if p>50: C['over 50']+=1; continue
    if d is None: C['no HT row, not traded']+=1; continue
    rows.append((e,o,str(group(ev)),d,1/p,ly(p,d)))
print("counted:",dict(sorted(C.items())),flush=True); print("settle v official HT winner on seen games:",dict(chk),flush=True)
R=pd.DataFrame(rows,columns='e off g won imp v'.split()); assert R.e.is_unique; md=np.median(R.off.values); R['h']=np.where(R.off<md,1,2)
print("by month:",pd.to_datetime(R.off,unit='s').dt.strftime('%Y-%m').value_counts().sort_index().to_dict(),"median date",pd.to_datetime(md,unit='s'),flush=True)
out=[]
for nm,x in (('HT DRAW lay, all (scored)',R),('senior only (context)',R[R.g=='None']),('women, youth (context)',R[R.g!='None'])):
    if not len(x): continue
    l=line(x.v.values,x.h.values); out.append(dict(line=nm,n=l['n'],games=x.e.nunique(),per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],won=x.won.mean(),imp=x.imp.mean(),PASS=l['PASS']))
O=pd.DataFrame(out); print("\n"+O.round(3).to_string(index=False))
S=O[O.PASS&O.line.str.contains('scored')]; print(f"\n== SURVIVORS: {len(S)} of 1\n",S.round(3).to_string(index=False) if len(S) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
