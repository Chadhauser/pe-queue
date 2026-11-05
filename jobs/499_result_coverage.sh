#!/bin/bash
set -o pipefail
# 499_result_coverage (Finder 2026-11-05, with queue item 144): is the part of Sep 2026 that holds official results (bf_hist_result) a fair sample? Not a trading test. Read only.
# Why: the loader's current Soccer list takes 18 countries only (SPEC in /root/pe-hist/loader_core.py), and files read before job 521's patch were marked done with no result. So Sep games fall into three groups: RESULT; LIST_NO_RESULT, same countries, read before the patch, split by load time and not by outcome; OFF_LIST.
# Test: Over 2.5 prints against an independent score (goal_timeline, finished as in jobs/499_official_audit.sh). If results were selected on the outcome, RESULT's gap (won minus implied) would differ from LIST_NO_RESULT's.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import norm,loose,tstat
from lib_official import secs,last_in
LIST={'GB','ES','IT','DE','FR','PT','NL','BE','TR','SC','AT','CH','DK','SE','NO','GR','US','JP'}
def lab(ctry,has): return 'RESULT' if has else ('LIST_NO_RESULT' if ctry in LIST else 'OFF_LIST')
assert lab('GB',True)=='RESULT' and lab('GB',False)=='LIST_NO_RESULT' and lab('AR',False)=='OFF_LIST' and lab(None,False)=='OFF_LIST'
def welch(a,b):
    a,b=np.asarray(a,float),np.asarray(b,float); return (a.mean()-b.mean())/(a.var(ddof=1)/len(a)+b.var(ddof=1)/len(b))**.5
assert abs(welch([1,3],[1,3]))<1e-12 and abs(welch([3,5],[1,3])-2/((2/2+2/2)**.5))<1e-9
print("checks: OK",flush=True); T0=time.time()
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
X=pd.read_sql("SELECT market_id,event_id,event_name ev,country ctry,market_time mt,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type='OVER_UNDER_25' AND market_id LIKE '1.%%' AND market_time>='2026-09-01' AND market_time<'2026-10-01' AND NOT inplay AND ltp>=1.01 AND ltp<1000 AND sel ILIKE 'over%%'",con)
HAS=set(pd.read_sql("SELECT DISTINCT market_id FROM bf_hist_result WHERE sport='Soccer' AND market_type='OVER_UNDER_25'",con).market_id)
lo_,hi_='2026-09-01','2026-10-03'
GT=pd.read_sql("SELECT DISTINCT ON (fixture_id) fixture_id,home_team,away_team,captured_at,minute,score_home,score_away,status FROM goal_timeline WHERE captured_at>=%s AND captured_at<%s AND score_home IS NOT NULL AND score_away IS NOT NULL ORDER BY fixture_id,captured_at DESC",con,params=(lo_,hi_)); con.close()
GT['t']=secs(GT.captured_at); GT['mn']=pd.to_numeric(GT.minute,errors='coerce')
GT=GT[GT.status.isin(['FT','Match Finished','FINISHED'])|((GT.mn>=88)&~GT.status.isin(['AET','PEN','ET']))].sort_values('t').reset_index(drop=True); GT['H']=GT.home_team.map(norm); GT['A']=GT.away_team.map(norm); tt=GT.t.values
X['tt']=secs(X.ts); X['off']=secs(X.mt); X=X.sort_values('tt',kind='stable'); rows=[]
for m,g in X.groupby('market_id'):
    o=float(g.off.iloc[0]); i=last_in(g.tt.values,o-1200,o-120)
    if i is None: continue
    ev=g.ev.iloc[0]; h,_x,a=ev.partition(' v '); lo,hi=np.searchsorted(tt,o),np.searchsorted(tt,o+14400); fx=loose(norm(h),norm(a),[(x.H,x.A,x.Index) for x in GT.iloc[lo:hi].itertuples()])
    over=np.nan
    if fx is not None: over=float(int(GT.score_home[fx])+int(GT.score_away[fx])>2.5)
    c=g.ctry.iloc[0]; rows.append((m,c,lab(c,m in HAS),1/float(g.ltp.values[i]),over))
R=pd.DataFrame(rows,columns='m c lab imp over'.split()); R['gap']=R.over-R.imp
print(f"Sep OU25 markets with a real-id print T-20 to T-2: {len(R)}, {time.time()-T0:.0f}s")
T=R.groupby('lab').agg(games=('m','size'),imp_all=('imp','mean'),scored=('over','count'),over=('over','mean'),imp=('imp',lambda s:s[R.loc[s.index,'over'].notna()].mean()),gap=('gap','mean')).round(4); print(T.to_string())
S=R[R.over.notna()]
for a,b in (('RESULT','LIST_NO_RESULT'),('RESULT','OFF_LIST')):
    u,v=S[S.lab==a].gap,S[S.lab==b].gap
    if len(u)>1 and len(v)>1: print(f"gap {a} minus {b}: {u.mean()-v.mean():+.4f}, Welch t {welch(u,v):.2f}, n {len(u)} v {len(v)}")
print("list countries by group:",R[R.c.isin(LIST)].groupby('lab').size().to_dict())
print("\n== SURVIVORS: not a price test, none"); print(f"total {time.time()-T0:.0f}s")
PY
