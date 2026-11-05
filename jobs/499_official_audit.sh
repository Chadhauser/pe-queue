#!/bin/bash
set -o pipefail
# 499_official_audit (Finder 2026-11-05, items 141-143): is bf_hist_result right? 499_longtail_official's audit matched no game at all, so this one prints why and tries both score sources. Results and scores only, no prices read. Read only.
# A independent: goal_timeline and af_fixtures final scores against official MO and OU25, loose name match, kick-off within 4 h after market time for the feed, 12 h either side for af. B logic between official markets of one event, needs no second source: OU lines nest, BTTS Yes needs Over 1.5, FH Over 0.5 implies FT Over 0.5, MO Draw with Over 0.5 needs Over 1.5. C event ids on one market per type.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import norm,loose
from lib_official import secs,load_results
def agree(mty,w,h,a,sh,sa):
    if mty=='MATCH_ODDS': return w=='The Draw' if sh==sa else norm(w)==norm(h if sh>sa else a)   # runner and event names differ in case and spelling
    return w.lower().startswith('over')==(sh+sa>2.5)
assert agree('MATCH_ODDS','Hull','Hull','Leeds',2,1) and not agree('MATCH_ODDS','Leeds','Hull','Leeds',2,1) and agree('MATCH_ODDS','The Draw','Hull','Leeds',1,1)
assert agree('OVER_UNDER_25','Over 2.5 Goals','x','y',2,1) and not agree('OVER_UNDER_25','Over 2.5 Goals','x','y',1,1) and agree('OVER_UNDER_25','Under 2.5 Goals','x','y',1,1)
print("checks: OK",flush=True); T0=time.time()
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='600s'")
TY=['MATCH_ODDS','OVER_UNDER_05','OVER_UNDER_15','OVER_UNDER_25','OVER_UNDER_35','OVER_UNDER_45','BOTH_TEAMS_TO_SCORE','FIRST_HALF_GOALS_05']
R=pd.read_sql("SELECT event_id,market_id,market_type,sel,status FROM bf_hist_result WHERE sport='Soccer' AND market_type=ANY(%s)",con,params=(TY,))
W=R[R.status=='WINNER']; n=W.groupby('market_id').size(); print(f"markets {R.market_id.nunique()}, winners per market {n.value_counts().to_dict()}")
print("settled share won by type:");
tag=W.assign(over=W.sel.str.lower().str.startswith(('over','yes')))
print(tag[tag.market_type!='MATCH_ODDS'].groupby('market_type').over.agg(['size','mean']).round(3).to_string())
draw=W[W.market_type=='MATCH_ODDS']; print(f"MO draws {(draw.sel=='The Draw').mean():.3f} of {len(draw)}")
# B: logic between markets
E={}
for r in tag.itertuples(): E.setdefault(r.event_id,{})[r.market_type]=(r.sel,r.over)
B=Counter(); nest=['OVER_UNDER_05','OVER_UNDER_15','OVER_UNDER_25','OVER_UNDER_35','OVER_UNDER_45']
for e,d in E.items():
    for lo,hi in zip(nest,nest[1:]):
        if lo in d and hi in d: B['nest tested']+=1; B['nest BAD']+=int(d[hi][1] and not d[lo][1])
    if 'BOTH_TEAMS_TO_SCORE' in d and 'OVER_UNDER_15' in d: B['btts tested']+=1; B['btts BAD']+=int(d['BOTH_TEAMS_TO_SCORE'][1] and not d['OVER_UNDER_15'][1])
    if 'FIRST_HALF_GOALS_05' in d and 'OVER_UNDER_05' in d: B['fh tested']+=1; B['fh BAD']+=int(d['FIRST_HALF_GOALS_05'][1] and not d['OVER_UNDER_05'][1])
    if 'MATCH_ODDS' in d and 'OVER_UNDER_05' in d and 'OVER_UNDER_15' in d and d['MATCH_ODDS'][0]=='The Draw': B['draw tested']+=1; B['draw BAD']+=int(d['OVER_UNDER_05'][1] and not d['OVER_UNDER_15'][1])
print("logic between official markets:",dict(sorted(B.items())),flush=True)
# A: independent scores
cur.execute("SELECT DISTINCT market_id,event_name,market_type,market_time FROM bf_hist_other WHERE sport='Soccer' AND market_id=ANY(%s) AND market_type IN ('MATCH_ODDS','OVER_UNDER_25')",(list(W[W.market_type.isin(['MATCH_ODDS','OVER_UNDER_25'])].market_id),))
MK=pd.DataFrame(cur.fetchall(),columns='market_id ev mty mt'.split()); MK['off']=secs(MK.mt); WN=dict(zip(W.market_id,W.sel))
lo_,hi_=str(MK.mt.min())[:10],str(MK.mt.max()+pd.Timedelta(days=2))[:10]; print(f"markets to check {len(MK)}, window {lo_} to {hi_}")
GT=pd.read_sql("SELECT DISTINCT ON (fixture_id) fixture_id,home_team,away_team,captured_at,minute,score_home,score_away,status FROM goal_timeline WHERE captured_at>=%s AND captured_at<%s AND score_home IS NOT NULL AND score_away IS NOT NULL ORDER BY fixture_id,captured_at DESC",con,params=(lo_,hi_))
print("goal_timeline last-row status:",GT.status.value_counts().head(8).to_dict())
GT['t']=secs(GT.captured_at); GT['mn']=pd.to_numeric(GT.minute,errors='coerce')
GT=GT[GT.status.isin(['FT','Match Finished','FINISHED'])|((GT.mn>=88)&~GT.status.isin(['AET','PEN','ET']))].sort_values('t').reset_index(drop=True); GT['H']=GT.home_team.map(norm); GT['A']=GT.away_team.map(norm); print(f"goal_timeline finished rows {len(GT)}",flush=True); tt=GT.t.values
cur.execute("SELECT column_name FROM information_schema.columns WHERE table_name='af_fixtures'"); cols=[x[0] for x in cur.fetchall()]; print("af_fixtures columns:",cols)
hn,an=('home_name','away_name') if 'home_name' in cols else ('home','away') if 'home' in cols else ('home_team','away_team')
AF=pd.read_sql(f"SELECT fixture_id,{hn} h,{an} a,kickoff,hg,ag FROM af_fixtures WHERE kickoff>=%s AND kickoff<%s AND status='FT' AND hg IS NOT NULL",con,params=(lo_,hi_)); con.close()
AF['t']=secs(AF.kickoff); AF=AF.sort_values('t').reset_index(drop=True); AF['H']=AF.h.map(norm); AF['A']=AF.a.map(norm); ta=AF.t.values; print(f"af_fixtures FT rows {len(AF)}",flush=True)
C=Counter(); bad=[]; badaf=[]
for r in MK.itertuples():
    h,_x,a=r.ev.partition(' v '); w=WN[r.market_id]; N1,N2=norm(h),norm(a)
    i,j=np.searchsorted(tt,r.off),np.searchsorted(tt,r.off+14400); fx=loose(N1,N2,[(x.H,x.A,x.Index) for x in GT.iloc[i:j].itertuples()])
    if fx is None: C[r.mty+' feed no match']+=1
    else:
        g=GT.loc[fx]; ok=agree(r.mty,w,h,a,int(g.score_home),int(g.score_away)); C[r.mty+(' feed agree' if ok else ' feed DISAGREE')]+=1
        if not ok and len(bad)<8: bad.append((r.mty,r.ev,w,int(g.score_home),int(g.score_away),g.status,str(g.minute)))
    i,j=np.searchsorted(ta,r.off-43200),np.searchsorted(ta,r.off+43200); fx=loose(N1,N2,[(x.H,x.A,x.Index) for x in AF.iloc[i:j].itertuples()])
    if fx is None: C[r.mty+' af no match']+=1
    else:
        g=AF.loc[fx]; ok=agree(r.mty,w,h,a,int(g.hg),int(g.ag)); C[r.mty+(' af agree' if ok else ' af DISAGREE')]+=1
        if not ok: badaf.append((r.mty,r.ev,w,int(g.hg),int(g.ag)))
print("independent check:",dict(sorted(C.items()))); print("feed disagreements, first 8:",bad); print("af disagreements, all:",badaf)
print(f"\n== SURVIVORS: not a price test, none\ntotal {time.time()-T0:.0f}s")
PY
