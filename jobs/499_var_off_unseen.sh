#!/bin/bash
set -o pipefail
# 499_var_off_unseen (Finder 2026-11-07, queue item 404, Finder's own, source a; rule from jobs/499_let_off.sh, match from jobs/lib_afmatch.py): lay the opponent after a goal cancelled by VAR at a level score, E5, settle. Games not in af_price_map. Rule in the queue before this read. Read only, no tables written. LTP only, so a pass is an upper bound.
# is_home on a VAR row is taken as the team the call went against, not checked (jobs/499_let_off.sh line 8), so TEAM is read beside OPP. Only OPP LAY level is scored.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import defaultdict,Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line
import lib_cand,lib_official,lib_afmatch; lib_cand._checks(); lib_official.checks(); lib_afmatch.checks()
from lib_afmatch import *
from lib_official import secs
pd.set_option('display.width',230); pd.set_option('display.max_rows',80); pd.set_option('display.max_columns',30)
T0=time.time(); A,B='2023-08-01','2026-10-01'
def is_level(goals,c):
    """goals (minute, is_home). Level at the event if each side has half the goals at or before c. No own-goal flip, as item 84."""
    s=[g for g in goals if g[0]<=c]; return sum(1 for g in s if g[1])*2==len(s)
def win(c): return clock_min(c+5),clock_min(c+7)
assert is_level([],30) and is_level([(10,True),(20,False)],30) and not is_level([(10,True)],30) and is_level([(40,True)],30)
assert win(30)==(35,37) and win(60)==(84,86)
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
F=fixtures(con,A,B); MK=match(con,'MATCH_ODDS',A,B,F); print(f"fixtures {len(F):,}, MO markets matched {len(MK):,}, {time.time()-T0:.0f}s",flush=True)
FI=F.set_index('fixture_id')
EV=pd.read_sql("SELECT fixture_id,coalesce(minute,0) AS minute,is_home,type,detail FROM af_events WHERE fixture_id=ANY(%s) AND is_home IS NOT NULL AND ((type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal')) OR (type='Var' AND detail='Goal cancelled'))",con,params=(list(map(int,MK.fx)),))
GL=defaultdict(list); X={}
for r in EV.sort_values(['fixture_id','minute']).itertuples():
    if r.type=='Goal': GL[r.fixture_id].append((int(r.minute),bool(r.is_home)))
    else: X.setdefault(r.fixture_id,(int(r.minute),bool(r.is_home)))
print("first VAR goal-off by season",pd.Series({k:FI.loc[k].season for k in X}).value_counts().sort_index().to_dict(),flush=True)
K=MK[MK.fx.isin(X)]; mids=list(K.market_id); PX={}
for c in range(0,len(mids),500):
    P=pd.read_sql("SELECT market_id,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type='MATCH_ODDS' AND market_id=ANY(%s) AND inplay AND ltp>=1.01 AND ltp<1000",con,params=(mids[c:c+500],))
    if not len(P): continue
    P['tt']=secs(P.ts); P=P.drop_duplicates(['market_id','sel','tt']).sort_values('tt',kind='stable')
    for k,x in P.groupby(['market_id','sel'],sort=False): PX[k]=(x.tt.values,x.ltp.values)
con.close(); print(f"tapes {len(PX):,}, {time.time()-T0:.0f}s",flush=True)
rows=[]; SK=Counter()
for r in K.itertuples():
    f=FI.loc[r.fx]; ko=f.k.timestamp(); c,ih=X[r.fx]
    if c>85: SK['after 85']+=1; continue
    h,_x,a=str(r.event_name).partition(' v '); nm={True:h.strip(),False:a.strip()}; wn={True:f.hg>f.ag,False:f.ag>f.hg}
    lv='level' if is_level(GL.get(r.fx,[]),c) else 'not level'
    for leg,side_home in (('OPP',not ih),('TEAM',ih)):
        x=PX.get((r.market_id,nm[side_home]))
        if x is None: SK[f'{leg} no tape by name']+=1; continue
        for side in 'BL':
            lo,hi=win(c); e=entry(x[0],x[1],ko,lo,hi,side)
            if e is None: SK[f'{leg} {side} no print or no bet']+=1; continue
            rows.append((leg,'BACK' if side=='B' else 'LAY',lv,ko,int(f.season),r.fx,pnl(side,e[1],wn[side_home]),wn[side_home],1/e[1]))
print("counts",dict(SK),flush=True)
T=pd.DataFrame(rows,columns='leg side lv off season g v won imp'.split()); assert not T.duplicated(['leg','side','g']).any(); o=[]
for (lg,s,lv),x in T.groupby(['leg','side','lv']):
    l=line(x.v.values,half(x.off.values)); sc=(lg=='OPP' and s=='LAY' and lv=='level')
    o.append(dict(line=f'VAR_GOAL_OFF {lg} {s} E5 settle {lv}',scored=sc,n=l['n'],per10=round(l['per10'],3),t=round(l['t'],2),h1=round(l['h1'],3),h2=round(l['h2'],3),n1=l['n1'],n2=l['n2'],won=round(x.won.mean(),3),imp=round(x.imp.mean(),3),ex_top=round((x.v.sum()-x.v.max())/max(len(x)-1,1),3),PASS=l['PASS'] and sc))
L=pd.DataFrame(o).sort_values('t',ascending=False); print(L.to_string(index=False))
Z=T[(T.leg=='OPP')&(T.side=='LAY')&(T.lv=='level')]; print("\nScored line by season:"); print(Z.groupby('season').v.agg(['size','mean']).round(3).to_string())
S=L[L.PASS==True]; print(f"\n== SURVIVORS: {len(S)}"); print(S.to_string(index=False) if len(S) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
