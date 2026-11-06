#!/bin/bash
set -o pipefail
# 499_wom_ip (Finder 2026-11-06, queue item 200, source b Webb): weight of money in play, three-level book, MATCH_ODDS on the other sports, ip_tape, rolling, about 6 days. Rule pushed before prices were read (commit 560c0fd). The number 499 is reused: 450-499 are all taken.
# Replayed frames removed as jobs/497_clean_frames_racing_basketball.sh, using past data only. Entry at the next clean frame, exit first two-sided clean frame H min on, one tick adverse each way, 2% on profit, £10 risk. Market gone = settled from the last print, unresolved counted.
# MEMORY: as jobs/499_wom_tennis.sh: 8 GB box, no swap; address space capped; refuses to start under 1.5 GB available.
ulimit -v 2500000
export OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,warnings,psycopg2,pandas as pd,numpy as np
from collections import Counter
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_wom import ticks,trade_h,table
T0=time.time(); GAP=180
def imb_state(i):
    return 'BH' if i>=0.75 else 'LH' if i<=0.25 else 'CTRL' if 0.40<=i<=0.60 else None
def clean_mask(tm):
    tm=np.asarray(tm,dtype=float); out=np.ones(len(tm),dtype=bool); mx=-np.inf
    for i,v in enumerate(tm):
        if np.isnan(v): continue
        if v<mx: out[i]=False
        else: mx=v
    return out
def frame_clean(d):
    """d: market_id, ts, tm. Boolean per row: its frame is not a replay."""
    f=d.groupby(['market_id','ts'],sort=True).tm.max().reset_index()
    f['ok']=np.concatenate([clean_mask(g.tm.values) for _,g in f.groupby('market_id',sort=False)])
    return d[['market_id','ts']].merge(f[['market_id','ts','ok']],on=['market_id','ts'],how='left').ok.values
# known answers, as job 497
assert clean_mask([10,12,11,12,13,12.5]).tolist()==[True,True,False,True,True,False] and clean_mask([10,float('nan'),9,11]).tolist()==[True,True,False,True]
_d=pd.DataFrame(dict(market_id=['m']*6+['n'],ts=[1,1,2,2,3,3,1],tm=[100.,90.,120.,120.,110.,110.,5.]))
assert frame_clean(_d).tolist()==[True,True,True,True,False,False,True]
print("checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
avail=int(next(l for l in open('/proc/meminfo') if l.startswith('MemAvailable')).split()[1])/1e6
print(f"MemAvailable {avail:.1f} GB",flush=True)
if avail<1.5: print("== SURVIVORS: not run, under 1.5 GB available"); sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; c0=con.cursor(); c0.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
D=pd.read_sql("""SELECT sport,market_id,sel_id,extract(epoch from ts)::float8 ts,ltp::float8 ltp,back_px::float8 bp,lay_px::float8 lp,back3_sz::float8 b3,lay3_sz::float8 l3,total_matched::float8 tm
 FROM ip_tape WHERE market_type='MATCH_ODDS' AND sport NOT IN ('football','soccer','horse_racing','racing','greyhound_racing')""",con); con.close()
print("rows by sport",D.groupby('sport').market_id.agg(['size','nunique']).sort_values('size',ascending=False).head(12).to_dict('index'),flush=True)
ok=frame_clean(D); print(f"rows {len(D):,}, replayed frames removed {(~ok).mean():.3f}",flush=True)
_n=int(ok.sum()); D=D[ok].drop_duplicates().sort_values(['market_id','sel_id','ts','bp','lp','ltp','b3','l3'],kind='mergesort'); print(f"exact duplicates dropped {_n-len(D)}; ties on runner and time ordered by book",flush=True)
S=Counter(); rows=[]
for (mk,sid),x in D.groupby(['market_id','sel_id'],sort=False):
    t,ltp,bp,lp,b3,l3=[x[c].values for c in 'ts ltp bp lp b3 l3'.split()]; n=len(t)
    if n<5: S['short']+=1; continue
    sport=x.sport.iloc[0]; grp=sport if sport in ('basketball','tennis') else 'other'; mid=(bp+lp)/2
    with np.errstate(invalid='ignore',divide='ignore'):
        book=(bp>=1.2)&(lp<=10)&(lp>bp)
        g=book&(np.where(book,ticks(np.where(book,bp,2.0),np.where(book,lp,2.0)),99)<=4)
        imb=b3/(b3+l3)
        st_ok=np.r_[False,(np.abs(mid[1:]/mid[:-1]-1)<=0.05)&((t[1:]-t[:-1])<=GAP)]
    base=g&st_ok&((b3+l3)>=100)&(t-t[0]>=300); seen=set()
    for i in np.where(base)[0]:
        st=imb_state(imb[i])
        if st is None or st in seen: continue
        seen.add(st); k=i+1; S['signal']+=1
        if k>=n or t[k]-t[i]>GAP or not g[k]: S['no entry']+=1; continue
        band='<2.5' if bp[i]<2.5 else '2.5-10'
        for side in ('back','lay'):
            for H in (5,10):
                p,e,how,w=trade_h(side,t,bp,lp,ltp,k,H); S[how]+=1; S['wide exit']+=w
                if p is not None: rows.append((grp,st,side,H,band,p,e,mk,t[k]))
print("counts",dict(sorted(S.items())),flush=True)
R=pd.DataFrame(rows,columns='grp state side H band pnl exact ev ts'.split())
P=table(R,['grp','state','side','H','band'],'ITEM 200 weight of money, other sports MATCH_ODDS in play',control=('state','CTRL'))
print("\n== SURVIVORS (n >= 300, 150 per half, t >= 3.5, both halves > 0, mean >= +0.15; games = markets, see tg)")
print('200','none' if P.empty else P.round(3).to_string(index=False))
print(f"total {time.time()-T0:.0f}s")
PY
