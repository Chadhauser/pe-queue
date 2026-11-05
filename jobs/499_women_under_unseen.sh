#!/bin/bash
set -o pipefail
# 499_women_under_unseen (Finder 2026-11-05, queue item 167, Finder's own, source c; from jobs/499_oct24_lines.sh, settle as jobs/499_fav_move_follow_unseen.sh): back Under 2.5 in women's football before the off, on events with no official result. Rule pushed in the queue before these prices were read. Read only.
# ENTRY last non-in-play print T-20 to T-2, worse of it and the next within 120 s, one tick adverse, 2%, £10, over 50 not traded. One bet per event, lowest id. Events not in bf_hist_result, May to 1 Oct 2026. Settled on the last goal_timeline row at minute 88+; no score match dropped, counted. Senior the same way is a control, not scored. Prints only: a pass is an upper bound.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import norm,loose,line
from lib_official import group,bk,fill,last_in,secs,checks
import lib_cand; lib_cand._checks(); checks()
def under_won(sh,sa): return sh+sa<2.5
assert under_won(1,1) and not under_won(2,1) and under_won(0,0) and not under_won(3,0)
assert abs(bk(2.04,True)-9.996)<1e-9 and bk(2.04,False)==-10.0
print("checks: OK",flush=True); T0=time.time()
pd.set_option('display.width',200); pd.set_option('display.max_columns',30)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
HAS=set(pd.read_sql("SELECT DISTINCT event_id FROM bf_hist_result WHERE sport='Soccer' AND market_type='OVER_UNDER_25'",con).event_id)
X=pd.read_sql("SELECT market_id,event_id,event_name ev,market_time mt,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type='OVER_UNDER_25' AND market_time>='2026-05-01' AND market_time<'2026-10-02' AND NOT inplay AND ltp>=1.01 AND ltp<1000 AND ts>=market_time-interval '21 min' AND lower(sel) LIKE 'under%%'",con)
GT=pd.read_sql("SELECT DISTINCT ON (fixture_id) fixture_id,home_team,away_team,captured_at,minute,score_home,score_away,status FROM goal_timeline WHERE captured_at>='2026-05-01' AND captured_at<'2026-10-03' AND score_home IS NOT NULL AND score_away IS NOT NULL ORDER BY fixture_id,captured_at DESC",con); con.close()
GT['t']=secs(GT.captured_at); GT['mn']=pd.to_numeric(GT.minute,errors='coerce')
GT=GT[(GT.mn>=88)&~GT.status.isin(['AET','PEN','ET'])].sort_values('t').reset_index(drop=True); GT['H']=GT.home_team.map(norm); GT['A']=GT.away_team.map(norm); tt=GT.t.values
X['tt']=secs(X.ts); X['off']=secs(X.mt); X=X.sort_values('tt',kind='stable')
ids=X.drop_duplicates('market_id')[['market_id','event_id']]; keep=ids.sort_values('market_id').drop_duplicates('event_id').market_id
X=X[X.market_id.isin(set(keep))&~X.event_id.isin(HAS)].drop_duplicates(['market_id','sel','tt'])
print(f"unseen OU25 events with an Under print {X.event_id.nunique()}, finished goal_timeline rows {len(GT)}, {time.time()-T0:.0f}s",flush=True)
C=Counter(); rows=[]
for e,g in X.groupby('event_id'):
    ev=g.ev.iloc[0]; o=float(g.off.iloc[0]); grp=group(ev)
    if grp=='YOUTH': C['youth']+=1; continue
    w=grp=='WOMEN'; ts,px=g.tt.values,g.ltp.values; i=last_in(ts,o-1200,o-120)
    if i is None: C[('W ' if w else 'S ')+'no print in window']+=1; continue
    p=fill(ts,px,i,'B')
    if p>50: C['over 50']+=1; continue
    hm,_x,aw=ev.partition(' v '); lo,hi=np.searchsorted(tt,o),np.searchsorted(tt,o+14400)
    fx=loose(norm(hm),norm(aw),[(z.H,z.A,z.Index) for z in GT.iloc[lo:hi].itertuples()])
    if fx is None: C[('W ' if w else 'S ')+'no score match, dropped']+=1; continue
    won=under_won(int(GT.score_home[fx]),int(GT.score_away[fx])); v=bk(p,won)
    if v is None: C['bottom of ladder, no back']+=1; continue
    rows.append((e,o,w,won,p,v))
print("counted:",dict(sorted(C.items())),flush=True)
R=pd.DataFrame(rows,columns='e off w won p v'.split()); assert R.e.is_unique
print("by month:",R.assign(m=pd.to_datetime(R.off,unit='s').dt.strftime('%Y-%m')).groupby(['m','w']).size().to_dict(),flush=True)
out=[]
for nm,x in (('WOMEN OU25 Under back (scored)',R[R.w]),('SENIOR OU25 Under back (control)',R[~R.w])):
    if not len(x): out.append(dict(line=nm,n=0,PASS=False)); continue
    l=line(x.v.values,np.where(x.off<np.median(x.off.values),1,2)); out.append(dict(line=nm,n=l['n'],games=x.e.nunique(),per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],won=x.won.mean(),imp=(1/x.p).mean(),PASS=l['PASS']))
O=pd.DataFrame(out); print("\n"+O.round(3).to_string(index=False))
S=O[O.line.str.contains('scored')&(O.PASS==True)]; print(f"\n== SURVIVORS: {len(S)} of 1\n",S.round(3).to_string(index=False) if len(S) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
