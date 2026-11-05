#!/bin/bash
set -o pipefail
# 499_lay_over25_all (Finder 2026-11-05, queue item 148, Finder's own, source c; from jobs/499_result_coverage.sh): Over 2.5 ran short of its price in all three Sep groups (gap -0.016, -0.007, -0.008). Is it enough to lay, on Aug 2026, which did not choose the idea? Read only.
# RULE fixed before any Aug price: one bet per game, deduped by event_id as the tape holds Sep OU25 twice under two market ids. Entry as item 141: last non-in-play Over 2.5 print T-20 to T-2, worse of it and the next print within 120 s, one tick adverse, 2%, £10 risk, hold to the result. Over 50 not traded. No cuts by league, price or country.
# SETTLE on goal_timeline finished rows as jobs/499_official_audit.sh (agreed 1,625 of 1,628 with official OU25). Aug has almost no official results, so games with no score match are dropped, counted, and their mean price shown: if it differs from the scored games, say so. Hold-out: Aug is the test; h1/h2 by date median inside it. Sep shown as the sample that suggested it, not as evidence.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import norm,loose,line
from lib_official import bk,ly,fill,last_in,secs,checks
import lib_cand; lib_cand._checks(); checks()
# one per event, whichever id: a duplicate tape must not add a bet
d=pd.DataFrame({'e':['a','a','b'],'m':['1.1','OU|x','1.2']}); assert len(d.sort_values('m').drop_duplicates('e'))==2
print("checks: OK",flush=True); T0=time.time()
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
out=[]
for mon,lo_,hi_ in (('2026-08','2026-08-01','2026-09-01'),('2026-09','2026-09-01','2026-10-01')):
    X=pd.read_sql("SELECT market_id,event_id,event_name ev,market_time mt,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type='OVER_UNDER_25' AND market_time>=%s AND market_time<%s AND NOT inplay AND ltp>=1.01 AND ltp<1000 AND sel ILIKE 'over%%'",con,params=(lo_,hi_))
    hi2=str((pd.Timestamp(hi_)+pd.Timedelta(days=2)).date())
    GT=pd.read_sql("SELECT DISTINCT ON (fixture_id) fixture_id,home_team,away_team,captured_at,minute,score_home,score_away,status FROM goal_timeline WHERE captured_at>=%s AND captured_at<%s AND score_home IS NOT NULL AND score_away IS NOT NULL ORDER BY fixture_id,captured_at DESC",con,params=(lo_,hi2))
    GT['t']=secs(GT.captured_at); GT['mn']=pd.to_numeric(GT.minute,errors='coerce')
    GT=GT[GT.status.isin(['FT','Match Finished','FINISHED'])|((GT.mn>=88)&~GT.status.isin(['AET','PEN','ET']))].sort_values('t').reset_index(drop=True); GT['H']=GT.home_team.map(norm); GT['A']=GT.away_team.map(norm); tt=GT.t.values
    X['tt']=secs(X.ts); X['off']=secs(X.mt); X=X.sort_values('tt',kind='stable')
    # the two ids hold the same prints: keep one id per event, real id first
    keep=X.drop_duplicates('market_id')[['market_id','event_id']].sort_values('market_id').drop_duplicates('event_id').market_id
    X=X[X.market_id.isin(set(keep))].drop_duplicates(['market_id','tt'])
    C=Counter(); rows=[]; unmatched=[]
    for e,g in X.groupby('event_id'):
        o=float(g.off.iloc[0]); ts,px=g.tt.values,g.ltp.values; i=last_in(ts,o-1200,o-120)
        if i is None: C['no print in window']+=1; continue
        ev=g.ev.iloc[0]; h,_x,a=ev.partition(' v '); lo,hi=np.searchsorted(tt,o),np.searchsorted(tt,o+14400); fx=loose(norm(h),norm(a),[(x.H,x.A,x.Index) for x in GT.iloc[lo:hi].itertuples()])
        if fx is None: C['no score match, dropped']+=1; unmatched.append(1/float(px[i])); continue
        won=int(GT.score_home[fx])+int(GT.score_away[fx])>2.5
        pl,pb=fill(ts,px,i,'L'),fill(ts,px,i,'B')
        if pl>50 or pb>50: C['over 50']+=1; continue
        vb=bk(pb,won)
        rows.append((e,o,won,1/float(px[i]),ly(pl,won),np.nan if vb is None else vb))
    R=pd.DataFrame(rows,columns='e off won imp lay back'.split()); md=np.median(R.off.values); h=np.where(R.off<md,1,2)
    print(f"\n{mon}: games {len(R)}, counted {dict(C)}, Over won {R.won.mean():.4f}, implied {R.imp.mean():.4f}, unmatched mean implied {np.mean(unmatched) if unmatched else float('nan'):.4f} v scored {R.imp.mean():.4f}, {time.time()-T0:.0f}s",flush=True)
    for nm,col in (('lay Over',R.lay),('back Over',R.back)):
        v=col.values; mask=~np.isnan(v); l=line(v[mask],h[mask]); out.append(dict(mon=mon,line=nm,n=l['n'],games=int(mask.sum()),per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],PASS=l['PASS']))
con.close(); O=pd.DataFrame(out); pd.set_option('display.width',200); print("\n"+O.round(3).to_string(index=False))
S=O[(O.mon=='2026-08')&O.PASS]; print(f"\n== SURVIVORS: {len(S)} on Aug 2026\n",S.round(3).to_string(index=False) if len(S) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
