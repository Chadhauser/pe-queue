#!/bin/bash
set -o pipefail
# 499_fh05_under_unseen (Finder 2026-11-05, queue item 149, Finder's own, source c; from jobs/499_longtail_senior.sh): pooled on the 3,058 official-result games, First Half Under 0.5 back made +0.341 (n 1,719) and Over 0.5 lay +0.387 (n 1,891), won 0.271 Under. Same event twice, and post hoc from 26 pooled lines. Does it hold on games that did not suggest it? Read only.
# RULE fixed before any unseen price: all games with a FIRST_HALF_GOALS_05 market, May-Sep 2026, NOT in bf_hist_result. Entry as item 141: last non-in-play print T-20 to T-2, worse of it and the next print within 120 s, one tick adverse, 2%, £10 risk, hold to half-time. Over 50 not traded. No cuts.
# SETTLE on goal_timeline status='HT' as jobs/499_fh3_older_months.sh. Games with no HT row dropped, counted, price compared. Regression first: the same feed against official FH05 on games that hold both; a low agreement voids the test. h1/h2 by date median.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import norm,loose,line
from lib_official import bk,ly,fill,last_in,secs,checks
import lib_cand; lib_cand._checks(); checks()
def sel_kind(s):
    s=str(s).strip().lower(); return 'Over' if s.startswith('over') else 'Under' if s.startswith('under') else None
assert sel_kind('Over 0.5 Goals')=='Over' and sel_kind('Under 0.5 Goals')=='Under' and sel_kind('The Draw') is None
def over_won(h,a): return h+a>0.5
assert over_won(1,0) and over_won(0,2) and not over_won(0,0)
print("checks: OK",flush=True); T0=time.time()
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
OFF=pd.read_sql("SELECT market_id,sel,status FROM bf_hist_result WHERE sport='Soccer' AND market_type='FIRST_HALF_GOALS_05' AND status='WINNER'",con); OW={m:sel_kind(s)=='Over' for m,s in zip(OFF.market_id,OFF.sel)}
X=pd.read_sql("SELECT market_id,event_id,event_name ev,market_time mt,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type='FIRST_HALF_GOALS_05' AND market_time>='2026-05-01' AND market_time<'2026-10-02' AND NOT inplay AND ltp>=1.01 AND ltp<1000",con)
AM=pd.read_sql("SELECT DISTINCT market_id,event_id,event_name ev,market_time mt FROM bf_hist_other WHERE sport='Soccer' AND market_type='FIRST_HALF_GOALS_05' AND market_time>='2026-05-01' AND market_time<'2026-10-02'",con)
GT=pd.read_sql("SELECT DISTINCT ON (fixture_id) fixture_id,home_team,away_team,captured_at,score_home h,score_away a FROM goal_timeline WHERE captured_at>='2026-05-01' AND captured_at<'2026-10-03' AND status='HT' AND score_home IS NOT NULL AND score_away IS NOT NULL ORDER BY fixture_id,captured_at DESC",con); con.close()
GT['t']=secs(GT.captured_at); GT=GT.sort_values('t').reset_index(drop=True); GT['H']=GT.home_team.map(norm); GT['A']=GT.away_team.map(norm); tt=GT.t.values
print(f"markets {AM.market_id.nunique()}, official {len(OW)}, HT rows {len(GT)}, {time.time()-T0:.0f}s",flush=True)
def ht(ev,o):
    h,_x,a=ev.partition(' v '); lo,hi=np.searchsorted(tt,o),np.searchsorted(tt,o+7200); fx=loose(norm(h),norm(a),[(x.H,x.A,x.Index) for x in GT.iloc[lo:hi].itertuples()])
    return None if fx is None else over_won(int(GT.h[fx]),int(GT.a[fx]))
AM['off']=secs(AM.mt); W={}; A=Counter()
for r in AM.itertuples(): W[r.market_id]=ht(r.ev,float(r.off))
for m,w in OW.items():
    if m in W: A['no HT row' if W[m] is None else 'agree' if W[m]==w else 'DISAGREE']+=1
print("regression, feed HT v official FH05:",dict(A),flush=True)
ag=A['agree']/max(1,A['agree']+A['DISAGREE']); assert ag>=0.97,f"settlement agreement {ag:.3f}, test void"
X['tt']=secs(X.ts); X['off']=secs(X.mt); X['k']=X.sel.map(sel_kind); X=X[X.k.notna()&~X.market_id.isin(set(OW))].drop_duplicates(['market_id','sel','tt']).sort_values('tt',kind='stable')
C=Counter(); rows=[]; un=[]
for (m,k),g in X.groupby(['market_id','k']):
    o=float(g.off.iloc[0]); ts,px=g.tt.values,g.ltp.values; i=last_in(ts,o-1200,o-120)
    if i is None: C[k+' no print in window']+=1; continue
    w=W.get(m)
    if w is None: C[k+' no HT row, dropped']+=1; un.append(1/float(px[i])); continue
    won=w if k=='Over' else not w
    p=fill(ts,px,i,'L' if k=='Over' else 'B')
    if p>50: C['over 50']+=1; continue
    v=ly(p,won) if k=='Over' else bk(p,won)
    if v is None: C['bottom of ladder']+=1; continue
    rows.append((m,k,o,won,1/p,v))
print("counted:",dict(sorted(C.items())),"mean implied of dropped",round(float(np.mean(un)),4) if un else None,flush=True)
R=pd.DataFrame(rows,columns='m k off won imp v'.split()); md=np.median(R.off.values); R['h']=np.where(R.off<md,1,2)
print("trades by month:",pd.to_datetime(R.off,unit='s').dt.strftime('%Y-%m').value_counts().sort_index().to_dict(),"median",pd.to_datetime(md,unit='s'))
out=[]
for k,nm in (('Under','FH05 Under back'),('Over','FH05 Over lay')):
    x=R[R.k==k]; l=line(x.v.values,x.h.values); out.append(dict(line=nm,n=l['n'],games=x.m.nunique(),per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],won=x.won.mean(),imp=x.imp.mean(),PASS=l['PASS']))
O=pd.DataFrame(out); pd.set_option('display.width',200); print("\n"+O.round(3).to_string(index=False))
S=O[O.PASS]; print(f"\n== SURVIVORS: {len(S)} of {len(O)}\n",S.round(3).to_string(index=False) if len(S) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
