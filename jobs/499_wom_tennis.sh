#!/bin/bash
set -o pipefail
# 499_wom_tennis (Finder 2026-11-06, queue item 197, source b Webb): weight of money at the top of the book, tennis MO in play, stream_ticks, rolling, about 4 days, pilot. Rule pushed before prices were read (queue commit 1105be6). Split from jobs/499_wom_stream.sh after that job was OOM-killed; rule unchanged. The number 499 is reused: 450-499 are all taken.
# Sampled once a minute, tick no older than 30 s. Entry next tick within 60 s, one tick adverse. Exit first two-sided tick H minutes on, one tick adverse. Market gone = settled from the last print, unresolved counted. 2% on profit, £10 risk (lib_wom, lib_cand).
# MEMORY: the box has 8 GB, no swap. Named cursor into numeric arrays, no pandas load; address space capped so this job dies alone; refuses to start under 1.5 GB available.
ulimit -v 2500000
export OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,warnings,psycopg2,pandas as pd,numpy as np
from collections import Counter
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_wom import ticks,trade_h,table
T0=time.time()
def imb_state(i):
    return 'BH' if i>=0.75 else 'LH' if i<=0.25 else 'CTRL' if 0.40<=i<=0.60 else None
def gate(b,l,bs,ls):
    """Signal book: price 1.2-10, spread <= 4 ticks, £50 on the top of the book."""
    return b==b and l==l and b>=1.2 and l<=10 and l>b and ticks(b,l)<=4 and bs==bs and ls==ls and bs+ls>=50
assert gate(2.0,2.04,30,30) and not gate(2.0,2.12,30,30) and not gate(1.1,1.12,30,30) and not gate(2.0,2.04,20,20) and not gate(9.8,10.5,30,30)
assert [imb_state(x) for x in (0.75,0.25,0.5,0.7)]==['BH','LH','CTRL',None]
print("checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
avail=int(next(l for l in open('/proc/meminfo') if l.startswith('MemAvailable')).split()[1])/1e6
print(f"MemAvailable {avail:.1f} GB",flush=True)
if avail<1.5: print("== SURVIVORS: not run, under 1.5 GB available"); sys.exit(0)
con=psycopg2.connect(creds.pg_local()); cur0=con.cursor(); cur0.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
cur=con.cursor('wom_tennis'); cur.itersize=200000
cur.execute("""SELECT market_id,sel_id,extract(epoch from ts_recv)::float8,back_px::float8,lay_px::float8,back_sz::float8,lay_sz::float8,ltp::float8
 FROM stream_ticks WHERE sport='tennis' AND mkt='MO' AND inplay AND status='OPEN'""")
MK={}; IDS=[]; NUM=[]; nr=0
while True:
    b=cur.fetchmany(200000)
    if not b: break
    IDS.append(np.array([(MK.setdefault(r[0],len(MK)),r[1]) for r in b],dtype=np.int64))
    NUM.append(np.array([r[2:] for r in b],dtype=np.float64)); nr+=len(b); del b    # None becomes nan
cur.close(); con.close()
IDS=np.concatenate(IDS); NUM=np.concatenate(NUM)
o=np.lexsort((NUM[:,5],NUM[:,4],NUM[:,3],NUM[:,2],NUM[:,1],NUM[:,0],IDS[:,1],IDS[:,0])); IDS=IDS[o]; NUM=NUM[o]; del o     # ties on runner and time ordered by book, so a re-read gives the same answer
_k=np.r_[True,(IDS[1:]!=IDS[:-1]).any(axis=1)|(np.nan_to_num(NUM[1:],nan=-1.)!=np.nan_to_num(NUM[:-1],nan=-1.)).any(axis=1)]; print(f"exact duplicates dropped {(~_k).sum()}",flush=True); IDS=IDS[_k]; NUM=NUM[_k]; del _k
print(f"197 ticks {nr:,}, markets {len(MK):,}, {pd.to_datetime(NUM[:,0].min(),unit='s')}..{pd.to_datetime(NUM[:,0].max(),unit='s')}",flush=True)
cut=np.r_[0,np.where((IDS[1:]!=IDS[:-1]).any(axis=1))[0]+1,len(IDS)]
S=Counter(); rows=[]
for a,b_ in zip(cut[:-1],cut[1:]):
    t,bp,lp,bs,ls,ltp=NUM[a:b_].T; mk=int(IDS[a,0]); seen=set()
    if len(t)<3: continue
    for g in np.arange(t[0]+60,t[-1],60.):
        i=int(np.searchsorted(t,g,side='right'))-1
        if g-t[i]>30 or not gate(bp[i],lp[i],bs[i],ls[i]): continue
        st=imb_state(bs[i]/(bs[i]+ls[i]))
        if st is None or st in seen: continue
        seen.add(st); k=i+1; S['197 signal']+=1
        if k>=len(t) or t[k]-t[i]>60 or not gate(bp[k],lp[k],bs[k],ls[k]): S['197 no entry']+=1
        else:
            band='<2.5' if bp[i]<2.5 else '2.5-10'
            for side in ('back','lay'):
                for H in (2,5,10):
                    p,e,how,w=trade_h(side,t,bp,lp,ltp,k,H); S['197 '+how]+=1; S['197 wide exit']+=w
                    if p is not None: rows.append((st,side,H,band,p,e,mk,t[k]))
        if len(seen)==3: break
print("counts",dict(sorted(S.items())),flush=True)
R=pd.DataFrame(rows,columns='state side H band pnl exact ev ts'.split())
P=table(R,['state','side','H','band'],'ITEM 197 weight of money, tennis MO in play',control=('state','CTRL'))
print("\n== SURVIVORS (n >= 300, 150 per half, t >= 3.5, both halves > 0, mean >= +0.15; 'games' = markets, both runners of a market can enter, see tg)")
print('197','none' if P.empty else P.round(3).to_string(index=False))
print(f"total {time.time()-T0:.0f}s")
PY
