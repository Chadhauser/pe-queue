#!/bin/bash
set -o pipefail
# FIX 2026-11-07: the +2 in clean_at, carried from jobs/499_fh3_aug24.sh, dropped goals up to 2 minutes AFTER the print, look-ahead that hurts a back and flatters a lay. CUSH keeps it, as item 212's rule; NOW drops only goals at or before the print, and is the read that counts. First run, void: n 5,206 +0.166 t 2.92.
# 499_fh3_lay_older (Finder 2026-11-07, queue item 405, from items 124, 138, 139; entry from jobs/499_fh3_augs.sh): lay FH25 Over at about 15 min at 0-0, Aug 2023 to Oct 2024. Rule in the queue before this read. Item 139 has shown the win rate on Aug and Sep of 2023 and 2024, so those four months are not blind: the 11 others are read apart. Read only, no tables written. LTP only, so a pass is an upper bound.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line
import lib_cand,lib_official,lib_afmatch; lib_cand._checks(); lib_official.checks(); lib_afmatch.checks()
from lib_afmatch import *
pd.set_option('display.width',230); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',40)
T0=time.time()
SEEN=('2023-08','2023-09','2024-08','2024-09')
def clean_at(t,off,goals,c=0): return not any(g<=(t-off)/60+c for g in goals)
def months(a,b):
    """Month starts from a to b inclusive, as (start, next start)."""
    s=pd.date_range(a,b,freq='MS'); return [(x.strftime('%Y-%m-%d'),(x+pd.offsets.MonthBegin(1)).strftime('%Y-%m-%d')) for x in s]
assert clean_at(1000.,100.,[18],2) and not clean_at(1000.,100.,[17],2) and clean_at(1000.,100.,[16]) and not clean_at(1000.,100.,[15])
assert months('2023-11-01','2024-01-01')==[('2023-11-01','2023-12-01'),('2023-12-01','2024-01-01'),('2024-01-01','2024-02-01')]
# Lay 15 -> 15.5 (one tick), stake 10/14.5 = 0.689655, wins 0.675862 after 2%; loses -10.
assert abs(pnl('L',15.5,False)-10/14.5*.98)<1e-9 and pnl('L',15.5,True)==-10.0
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
ALL=[]; chk=[]; SK=Counter()
for A,B in months('2023-08-01','2024-10-01'):
    F=fixtures(con,A,B,unmapped_only=False); F=F[F.ht_hg.notna()&F.ht_ag.notna()].reset_index(drop=True)
    MK=match(con,'FIRST_HALF_GOALS_25',A,B,F); FI=F.set_index('fixture_id')
    EV=pd.read_sql("SELECT fixture_id,coalesce(minute,0) mn FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal')",con,params=(list(map(int,MK.fx)),))
    GL={k:list(v.mn) for k,v in EV.groupby('fixture_id')}
    PX=tape(con,'FIRST_HALF_GOALS_25',list(MK.market_id),'over'); OF=official_over(con,list(MK.market_id))
    for r in MK.itertuples():
        f=FI.loc[r.fx]; off=r.mt.timestamp(); won=(f.ht_hg+f.ht_ag)>2.5; x=PX.get(r.market_id)
        if x is None: SK['no in-play Over print']+=1; continue
        chk.append((won,OF.get(r.market_id)))
        e=entry(x[0],x[1],off,15,1199/60,'L')
        if e is None: SK['no print in the window']+=1; continue
        i,a=e
        if a>200: SK['over 200']+=1; continue
        if not clean_at(x[0][i],off,GL.get(r.fx,[])): SK['not 0-0 at the print']+=1; continue
        ALL.append((A[:7],r.fx,off,a,won,pnl('L',a,won),clean_at(x[0][i],off,GL.get(r.fx,[]),2)))
    print(f"{A[:7]} markets {len(MK):,}, {time.time()-T0:.0f}s",flush=True)
con.close(); print("counts",dict(SK),flush=True)
ag,ck=agreement(chk); print(f"af HT score v official FH25 result: {ag} of {ck} agree, {ag/max(ck,1):.3f}",flush=True)
R=pd.DataFrame(ALL,columns='mo g off a won v cush'.split()); assert not R.duplicated('g').any(); out=[]
def rd(nm,x,sc):
    l=line(x.v.values,half(x.off.values)); out.append(dict(line=nm,scored=sc,n=l['n'],games=x.g.nunique(),per10=round(l['per10'],3),t=round(l['t'],2),h1=round(l['h1'],3),h2=round(l['h2'],3),n1=l['n1'],n2=l['n2'],won=round(x.won.mean(),3),imp=round((1/x.a).mean(),3),ex_top=round((x.v.sum()-x.v.max())/max(len(x)-1,1),3),PASS=l['PASS'] and sc))
rd('ALL 15 months NOW',R,True); rd('ALL 15 months CUSH',R[R.cush],False); rd('11 months item 139 never read',R[~R.mo.isin(SEEN)],False); rd('4 months item 139 read',R[R.mo.isin(SEEN)],False)
for mo,x in R.groupby('mo'): rd(mo,x,False)
L=pd.DataFrame(out); print(L.to_string(index=False)); S=L[L.PASS==True]; print(f"\n== SURVIVORS: {len(S)}"); print(S.to_string(index=False) if len(S) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
