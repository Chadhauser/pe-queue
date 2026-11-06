#!/bin/bash
set -o pipefail
# 499_wom_stream (Finder 2026-11-06, queue item 195, source b Webb): weight of money at the top of the book. Football MO_PRE before the off, stream_ticks, rolling, about 4 days, pilot. Item 197 (tennis) was in this job until it was OOM-killed at about 3 GB in pandas; it is now jobs/499_wom_tennis.sh. Rules pushed before prices were read (queue commit 1105be6). The number 499 is reused: 450-499 are all taken.
# Entry at the next tick, as a trader cannot act on the signal's own tick. One tick adverse each way, 2% on profit, £10 risk (lib_wom, lib_cand). Pre-off positions never settle.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,warnings,psycopg2,pandas as pd,numpy as np
from collections import Counter
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_wom import ticks,table,two_sided,entry_px,pnl_exit
T0=time.time(); EXIT=300
def imb_state(i):
    return 'BH' if i>=0.75 else 'LH' if i<=0.25 else 'CTRL' if 0.40<=i<=0.60 else None
def gate(b,l,bs,ls):
    """Signal book: price 1.2-10, spread <= 4 ticks, £50 on the top of the book."""
    return b==b and l==l and b>=1.2 and l<=10 and l>b and ticks(b,l)<=4 and bs==bs and ls==ls and bs+ls>=50
assert gate(2.0,2.04,30,30) and not gate(2.0,2.12,30,30) and not gate(1.1,1.12,30,30) and not gate(2.0,2.04,20,20) and not gate(9.8,10.5,30,30)
def anchor_row(s,A):
    """Last row at or before T-A on a pre-off clock s (seconds to off, falling). None if there is none no older than 300 s."""
    i=int(np.searchsorted(-s,-A,side='right'))-1
    return i if i>=0 and s[i]-A<=300 else None
_s=np.array([4000.,3700,3650,3500,1000])
assert anchor_row(_s,3600)==2 and anchor_row(_s,900)==4 and anchor_row(_s,600) is None and anchor_row(_s,5000) is None and anchor_row(_s,3400)==3   # T-1000 is 100 s old at T-900, 400 s old at T-600
print("checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
# item 195
D=pd.read_sql("""SELECT market_id,sel_id,extract(epoch from ts_recv)::float8 t,secs_to_off::float8 s,back_px::float8 bp,lay_px::float8 lp,back_sz::float8 bs,lay_sz::float8 ls
 FROM stream_ticks WHERE sport='football' AND mkt='MO_PRE' AND NOT inplay AND status='OPEN' AND secs_to_off BETWEEN 300 AND 4200""",con)
_n=len(D); D=D.drop_duplicates().sort_values(['market_id','sel_id','t','bp','lp','bs','ls'],kind='mergesort'); print(f"exact duplicates dropped {_n-len(D)}; ties on sel and time ordered by book, so a re-read gives the same answer",flush=True); print(f"195 ticks {len(D):,}, markets {D.market_id.nunique():,}, {pd.to_datetime(D.t.min(),unit='s')}..{pd.to_datetime(D.t.max(),unit='s')}",flush=True)
S=Counter(); rows=[]
for (mk,sid),x in D.groupby(['market_id','sel_id'],sort=False):
    t,s,bp,lp,bs,ls=[x[c].values for c in 't s bp lp bs ls'.split()]
    for A in (3600,1800,900):
        i=anchor_row(s,A)
        if i is None: S['195 no anchor']+=1; continue
        if not gate(bp[i],lp[i],bs[i],ls[i]): S['195 gate']+=1; continue
        st=imb_state(bs[i]/(bs[i]+ls[i]))
        if st is None: S['195 no state']+=1; continue
        k=i+1; S['195 signal']+=1
        if k>=len(t) or t[k]-t[i]>300 or s[k]<EXIT or not gate(bp[k],lp[k],bs[k],ls[k]): S['195 no entry']+=1; continue
        j=len(t)-1
        while j>k and not two_sided(bp[j],lp[j]): j-=1
        if j<=k: S['195 no exit']+=1; continue
        band='<2.5' if bp[i]<2.5 else '2.5-10'
        for side in ('back','lay'):
            a,a0=entry_px(side,bp[k],lp[k]); p,e=pnl_exit(side,a,a0,lp[j] if side=='back' else bp[j])
            rows.append((A,st,side,band,p,e,mk,t[k]))
print("counts",dict(sorted(S.items())),flush=True)
R=pd.DataFrame(rows,columns='anchor state side band pnl exact ev ts'.split())
P1=table(R,['anchor','state','side','band'],'ITEM 195 weight of money, football MO before the off',control=('state','CTRL')); del D,R
con.close()
print("\n== SURVIVORS (n >= 300, 150 per half, t >= 3.5, both halves > 0, mean >= +0.15; 'games' here = markets, all runners of a market can enter, see tg)")
for nm,P in (('195',P1),):
    print(nm,'none' if P.empty else P.round(3).to_string(index=False))
print(f"total {time.time()-T0:.0f}s")
PY
