#!/bin/bash
set -o pipefail
# 499_women_ou15_unseen (Finder 2026-11-06, queue item 269, Finder's own, source c; from jobs/499_women_under_unseen.sh): back Under 1.5 in women's football before the off, on games no read has used. Rule pushed in the queue before these prices. Read only. No tables written.
# ENTRY last non-in-play print T-20 to T-2, worse of it and the next within 120 s, one tick adverse, 2%, GBP 10, over 50 not traded. One bet per event, lowest id. GAMES Feb 2024 official, as loaded so far; May to 1 Oct 2026 games with no official result, settled on goal_timeline as item 167. 2026 games with an official result helped choose the line, left out and counted.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_000_000_000,2_000_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import norm,loose,line
from lib_official import group,bk,fill,last_in,secs,checks
import lib_cand; lib_cand._checks(); checks()
def under_won(sh,sa): return sh+sa<1.5
assert under_won(1,0) and under_won(0,0) and not under_won(1,1) and not under_won(2,0)
assert abs(bk(4.0,True)-(3.95-1)*10*.98)<1e-9 and bk(4.0,False)==-10.0   # 4.0 one tick adverse is 3.95; wins 29.5, 28.91 after 2%
assert abs(secs(pd.Series([pd.Timestamp('2024-02-01',tz='UTC')])).iloc[0]-1706745600)<1e-6
print("checks: OK",flush=True); T0=time.time()
pd.set_option('display.width',200); pd.set_option('display.max_columns',30)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
RS=pd.read_sql("SELECT market_id,event_id,sel,status FROM bf_hist_result WHERE sport='Soccer' AND market_type='OVER_UNDER_15'",con); HAS=set(RS.event_id)
U=RS[RS.sel.str.lower().str.startswith('under')]; w=RS[RS.status=='WINNER'].groupby('market_id').size(); ok=set(w[w==1].index); OFF={m:s=='WINNER' for m,s in zip(U.market_id,U.status) if m in ok}; print(f"official OU15 markets {RS.market_id.nunique():,}, with one winner {len(ok):,}",flush=True)
X=pd.read_sql("SELECT market_id,event_id,event_name ev,market_time mt,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type='OVER_UNDER_15' AND ((market_time>='2024-01-01' AND market_time<'2024-03-01') OR (market_time>='2026-05-01' AND market_time<'2026-10-02')) AND NOT inplay AND ltp>=1.01 AND ltp<1000 AND ts>=market_time-interval '20 minutes' AND lower(sel) LIKE 'under%'",con)
GT=pd.read_sql("SELECT DISTINCT ON (fixture_id) fixture_id,home_team,away_team,captured_at,minute,score_home,score_away,status FROM goal_timeline WHERE captured_at>='2026-05-01' AND captured_at<'2026-10-03' AND score_home IS NOT NULL AND score_away IS NOT NULL ORDER BY fixture_id,captured_at DESC",con); con.close()
GT['t']=secs(GT.captured_at); GT['mn']=pd.to_numeric(GT.minute,errors='coerce')
GT=GT[(GT.mn>=88)&~GT.status.isin(['AET','PEN','ET'])].sort_values('t').reset_index(drop=True); GT['H']=GT.home_team.map(norm); GT['A']=GT.away_team.map(norm); tt=GT.t.values
X['tt']=secs(X.ts); X['off']=secs(X.mt); X=X.sort_values('tt',kind='stable').drop_duplicates(['market_id','sel','tt'])
print(f"prints {len(X):,}, events {X.event_id.nunique():,}, {time.time()-T0:.0f}s",flush=True)
C=Counter(); rows=[]; seen=set(); CUT=pd.Timestamp('2024-03-01',tz='UTC').timestamp()
for m,g in X.groupby('market_id',sort=True):
    ev=g.ev.iloc[0]; o=float(g.off.iloc[0]); e=g.event_id.iloc[0]; grp=group(ev)
    if grp=='YOUTH': C['youth']+=1; continue
    w_=grp=='WOMEN'; tag='W ' if w_ else 'S '
    if (ev,o) in seen: C[tag+'second id']+=1; continue
    seen.add((ev,o))
    old=o<CUT
    if not old and e in HAS: C[tag+'2026 with official result, chose the line, left out']+=1; continue
    ts,px=g.tt.values,g.ltp.values; i=last_in(ts,o-1200,o-120)
    if i is None: C[tag+'no print in window']+=1; continue
    p=fill(ts,px,i,'B')
    if p>50: C[tag+'over 50']+=1; continue
    if old:
        if m not in OFF: C[tag+'Feb 2024 no official result, dropped']+=1; continue
        won=bool(OFF[m])
    else:
        hm,_x,aw=ev.partition(' v '); lo,hi=np.searchsorted(tt,o),np.searchsorted(tt,o+14400)
        fx=loose(norm(hm),norm(aw),[(z.H,z.A,z.Index) for z in GT.iloc[lo:hi].itertuples()])
        if fx is None: C[tag+'no score match, dropped']+=1; continue
        won=under_won(int(GT.score_home[fx]),int(GT.score_away[fx]))
    v=bk(p,won)
    if v is None: C['bottom of ladder, no back']+=1; continue
    rows.append((ev,o,w_,old,won,p,v))
print("counted:",dict(sorted(C.items())),flush=True)
R=pd.DataFrame(rows,columns='e off w old won p v'.split()); assert not R.duplicated(['e','off']).any()
print("by month:",R.assign(m=pd.to_datetime(R.off,unit='s').dt.strftime('%Y-%m')).groupby(['m','w']).size().to_dict(),flush=True)
out=[]
for nm,x in (('WOMEN OU15 Under back (scored)',R[R.w]),('of which Feb 2024',R[R.w&R.old]),('of which 2026',R[R.w&~R.old]),('SENIOR OU15 Under back (control)',R[~R.w])):
    if not len(x): out.append(dict(line=nm,n=0,PASS=False)); continue
    l=line(x.v.values,np.where(x.off<np.median(x.off.values),1,2)); out.append(dict(line=nm,n=l['n'],per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],maxwin=l['maxwin'],won=x.won.mean(),imp=(1/x.p).mean(),PASS=l['PASS']))
O=pd.DataFrame(out); print("\n"+O.round(3).to_string(index=False))
S=O[O.line.str.contains('scored')&(O.PASS==True)]; print(f"\n== SURVIVORS: {len(S)} of 1\n",S.round(3).to_string(index=False) if len(S) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
