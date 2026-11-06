#!/bin/bash
set -o pipefail
# 499_wom_passive (Finder 2026-11-06, queue items 198 tennis and 199 football, from items 194-197): weight of money, resting at the far touch instead of crossing. stream_ticks in play, rolling, about 4 days, pilot. Usage: 499_wom_passive.sh tennis|football. Rules pushed before prices were read (commit f78001c). A print-through fill is the pessimistic case: it leaves out fills at the price with no trade beyond it. The number 499 is reused: 450-499 are all taken.
# Filled only by a NEW print strictly through the resting price within 5 min (lib_wom.rest_fill). Fill one tick adverse, out by crossing H min on, one tick adverse, market gone = settled from the last print, unresolved counted. 2% on profit, £10 risk.
# Sampled once a minute, tick no older than 30 s. Prices are last-traded prints, so a fill is inferred from a print, not a real queue position.
# MEMORY: as jobs/499_wom_tennis.sh: 8 GB box, no swap. Named cursor into numeric arrays; address space capped; refuses to start under 1.5 GB available.
ulimit -v 2500000
export OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,warnings,psycopg2,pandas as pd,numpy as np
from collections import Counter
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_wom import ticks,trade_rest,rest_fill,table
T0=time.time(); SPORT=sys.argv[1]; ITEM={'tennis':'198','football':'199'}[SPORT]
def imb_state(i):
    return 'BH' if i>=0.75 else 'LH' if i<=0.25 else 'CTRL' if 0.40<=i<=0.60 else None
def gate(b,l,bs,ls):
    return b==b and l==l and b>=1.2 and l<=10 and l>b and ticks(b,l)<=4 and bs==bs and ls==ls and bs+ls>=50
assert gate(2.0,2.04,30,30) and not gate(2.0,2.12,30,30) and not gate(1.1,1.12,30,30) and not gate(2.0,2.04,20,20)
print("checks: OK",flush=True)
avail=int(next(l for l in open('/proc/meminfo') if l.startswith('MemAvailable')).split()[1])/1e6
print(f"MemAvailable {avail:.1f} GB",flush=True)
if avail<1.5: print("== SURVIVORS: not run, under 1.5 GB available"); sys.exit(0)
con=psycopg2.connect(creds.pg_local()); c0=con.cursor(); c0.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
cur=con.cursor('wom_passive'); cur.itersize=200000
cur.execute("""SELECT market_id,sel_id,extract(epoch from ts_recv)::float8,back_px::float8,lay_px::float8,back_sz::float8,lay_sz::float8,ltp::float8
 FROM stream_ticks WHERE sport=%s AND mkt='MO' AND inplay AND status='OPEN'""",(SPORT,))
MK={}; IDS=[]; NUM=[]; nr=0
while True:
    b=cur.fetchmany(200000)
    if not b: break
    IDS.append(np.array([(MK.setdefault(r[0],len(MK)),r[1]) for r in b],dtype=np.int64))
    NUM.append(np.array([r[2:] for r in b],dtype=np.float64)); nr+=len(b); del b
cur.close(); con.close()
IDS=np.concatenate(IDS); NUM=np.concatenate(NUM)
o=np.lexsort((NUM[:,5],NUM[:,4],NUM[:,3],NUM[:,2],NUM[:,1],NUM[:,0],IDS[:,1],IDS[:,0])); IDS=IDS[o]; NUM=NUM[o]; del o     # ties on runner and time ordered by book, so a re-read gives the same answer
_k=np.r_[True,(IDS[1:]!=IDS[:-1]).any(axis=1)|(np.nan_to_num(NUM[1:],nan=-1.)!=np.nan_to_num(NUM[:-1],nan=-1.)).any(axis=1)]; print(f"exact duplicates dropped {(~_k).sum()}",flush=True); IDS=IDS[_k]; NUM=NUM[_k]; del _k
print(f"{ITEM} ticks {nr:,}, markets {len(MK):,}, {pd.to_datetime(NUM[:,0].min(),unit='s')}..{pd.to_datetime(NUM[:,0].max(),unit='s')}",flush=True)
first={m:NUM[IDS[:,0]==m,0].min() for m in (range(len(MK)) if SPORT=='football' else [])}
cut=np.r_[0,np.where((IDS[1:]!=IDS[:-1]).any(axis=1))[0]+1,len(IDS)]
S=Counter(); rows=[]
for a,b_ in zip(cut[:-1],cut[1:]):
    t,bp,lp,bs,ls,ltp=NUM[a:b_].T; mk=int(IDS[a,0]); seen=set()
    if len(t)<3: continue
    for g in np.arange(t[0]+60,t[-1],60.):
        if SPORT=='football' and not (300<=g-first[mk]<=5400): continue
        i=int(np.searchsorted(t,g,side='right'))-1
        if g-t[i]>30 or not gate(bp[i],lp[i],bs[i],ls[i]): continue
        st=imb_state(bs[i]/(bs[i]+ls[i]))
        if st is None or st in seen: continue
        seen.add(st); S['signal']+=1
        band='<2.5' if bp[i]<2.5 else '2.5-10'
        for side,P in (('back',lp[i]),('lay',bp[i])):
            k=rest_fill(side,t,ltp,i,P,300)
            if k is None: S[side+' unfilled']+=1; continue
            S[side+' filled']+=1
            for H in (5,10):
                p,e,how,w=trade_rest(side,t,bp,lp,ltp,k,H,P); S[how]+=1; S['wide exit']+=w
                if p is not None: rows.append((st,side,H,band,p,e,mk,t[k]))
        if len(seen)==3: break
print("counts",dict(sorted(S.items())),flush=True)
R=pd.DataFrame(rows,columns='state side H band pnl exact ev ts'.split())
P_=table(R,['state','side','H','band'],f'ITEM {ITEM} weight of money, resting, {SPORT} MO in play',control=('state','CTRL'))
print(f"\n== SURVIVORS (n >= 300, 150 per half, t >= 3.5, both halves > 0, mean >= +0.15; games = markets, see tg)")
print(ITEM,'none' if P_.empty else P_.round(3).to_string(index=False))
print(f"total {time.time()-T0:.0f}s")
PY
