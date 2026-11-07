#!/bin/bash
set -o pipefail
# FIX 2026-11-07: the +2 in clean_at, carried from jobs/499_fh3_aug24.sh, dropped goals up to 2 minutes AFTER the print, look-ahead that hurts a back and flatters a lay. CUSH keeps it, as item 212's rule; NOW drops only goals at or before the print, and is the read that counts.
# 499_fh3_augs (Finder 2026-11-07, queue item 139, Finder's own, source c; rule from jobs/499_fh3_aug24.sh, match from jobs/lib_afmatch.py): back FH25 Over at about 15 min at 0-0, Aug 2023 and Aug 2024 scored, Sep of the same years the control. Aug 2025 is LISTFAIL at the loader. goal_timeline does not reach these months, so the score comes from af_events and af_fixtures: fixtures matched by name, all 29 leagues, and the clock stands in for the feed minute. Read only, no tables written. LTP only, so a pass is an upper bound.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line
import lib_cand,lib_official,lib_afmatch; lib_cand._checks(); lib_official.checks(); lib_afmatch.checks()
from lib_afmatch import *
pd.set_option('display.width',230); pd.set_option('display.max_columns',30)
T0=time.time()
def clean_at(t,off,goals,c=0):
    """No goal with af minute at or before the print's clock minute + c."""
    return not any(g<=(t-off)/60+c for g in goals)
assert clean_at(1000.,100.,[]) and clean_at(1000.,100.,[18],2) and not clean_at(1000.,100.,[17],2) and not clean_at(1000.,100.,[5],2) and clean_at(1000.,100.,[16]) and not clean_at(1000.,100.,[15])
# Back 41 -> 40 (one tick), win 390 less 2% = 382.2; lose -10.
assert abs(pnl('B',40.0,True)-382.2)<1e-9 and pnl('B',40.0,False)==-10.0
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
MAPPED=set(pd.read_sql("SELECT substr(understat_id,3)::bigint f FROM af_price_map",con).f)
out=[]; ALL=[]; chk=[]; SK=Counter()
for y in (2023,2024):
    A,B=f'{y}-08-01',f'{y}-10-01'
    F=fixtures(con,A,B,unmapped_only=False); F=F[F.ht_hg.notna()&F.ht_ag.notna()].reset_index(drop=True)
    MK=match(con,'FIRST_HALF_GOALS_25',A,B,F); print(f"{y}: fixtures {len(F):,}, FH25 markets matched {len(MK):,}, {time.time()-T0:.0f}s",flush=True)
    FI=F.set_index('fixture_id')
    EV=pd.read_sql("SELECT fixture_id,coalesce(minute,0) mn FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal')",con,params=(list(map(int,MK.fx)),))
    GL={k:list(v.mn) for k,v in EV.groupby('fixture_id')}
    PX=tape(con,'FIRST_HALF_GOALS_25',list(MK.market_id),'over'); OF=official_over(con,list(MK.market_id))
    for r in MK.itertuples():
        f=FI.loc[r.fx]; off=r.mt.timestamp(); won=(f.ht_hg+f.ht_ag)>2.5; x=PX.get(r.market_id)
        if x is None: SK['no in-play Over print']+=1; continue
        chk.append((won,OF.get(r.market_id)))
        e=entry(x[0],x[1],off,15,1199/60,'B')
        if e is None: SK['no print in the window or no bet']+=1; continue
        i,a=e
        if not clean_at(x[0][i],off,GL.get(r.fx,[])): SK['not 0-0 at the print']+=1; continue
        ALL.append((r.mt.strftime('%Y-%m'),r.fx,r.fx in MAPPED,off,a,won,pnl('B',a,won),clean_at(x[0][i],off,GL.get(r.fx,[]),2)))
con.close(); print("counts",dict(SK),flush=True)
ag,ck=agreement(chk); print(f"af HT score v official FH25 result: {ag} of {ck} agree, {ag/max(ck,1):.3f}",flush=True)
R=pd.DataFrame(ALL,columns='mo g mapped off a won v cush'.split()); assert not R.duplicated('g').any()
def rd(nm,x,sc):
    l=line(x.v.values,half(x.off.values)); out.append(dict(line=nm,scored=sc,n=l['n'],per10=round(l['per10'],3),t=round(l['t'],2),h1=round(l['h1'],3),h2=round(l['h2'],3),n1=l['n1'],n2=l['n2'],won=round(x.won.mean(),3),imp=round((1/x.a).mean(),3),ex_top=round((x.v.sum()-x.v.max())/max(len(x)-1,1),3),PASS=l['PASS'] and sc))
Aug=R[R.mo.str.endswith('-08')]; Sep=R[R.mo.str.endswith('-09')]
rd('ALL AUGUSTS NOW',Aug,True); rd('ALL SEPTEMBERS NOW control',Sep,False); rd('ALL AUGUSTS CUSH',Aug[Aug.cush],False); rd('ALL SEPTEMBERS CUSH',Sep[Sep.cush],False)
for mo,x in R.groupby('mo'): rd(mo,x,False)
rd('2024-08 mapped, item 212 read n 258 -0.649',R[(R.mo=='2024-08')&R.mapped],False); rd('2024-09 mapped, item 212 read n 323 -2.478',R[(R.mo=='2024-09')&R.mapped],False)
L=pd.DataFrame(out); print(L.to_string(index=False)); S=L[L.PASS==True]; print(f"\n== SURVIVORS: {len(S)}"); print(S.to_string(index=False) if len(S) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
