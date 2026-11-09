#!/bin/bash
set -o pipefail
# 499_round_number_racing (Finder 2026-11-09, 05:10 UTC run, queue item 484; adjacent door of item 482; join and settlement as jobs/499_bsp_loc.sh).
# Racing GB/IE WIN: each runner's last pre-off print T-5 to T-1 min, price 1.2-20.5. ROUND = print on 1.5 2 2.5 3 4 5 6 8 10 15 20; NEAR = one tick either side.
# One bet a race: the qualifying runner with the latest print. Entry at that print one tick adverse, £10 stake or liability, 2% on profit,
# held to racing_bsp win_lose (same-day name match, one row, event within 2 h). Halves by date median; t gate = smaller of per-trade and per-race.
# Scored lines (2): WIN ROUND back, WIN ROUND lay. Local DB, read-only, no tables written. No secrets printed.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(3_000_000_000,3_000_000_000))
import sys,re,time,unicodedata,warnings,psycopg2,pandas as pd,numpy as np
from collections import Counter,defaultdict
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,tstat,passes
from lib_official import last_in,checks,bk,ly
checks()
pd.set_option('display.width',230); pd.set_option('display.max_rows',200); pd.set_option('display.max_columns',30)
T0=time.time(); BUDGET=1500; M=60.0
ROUND=(1.5,2.0,2.5,3.0,4.0,5.0,6.0,8.0,10.0,15.0,20.0)
NEAR={}
for r in ROUND:
    NEAR[round(step(r,-1),2)]=r; NEAR[round(step(r,1),2)]=r
def cls(p):
    if p<1.2 or p>20.5: return None
    q=round(float(p),2)
    if any(abs(q-r)<1e-9 for r in ROUND): return 'ROUND',q
    if q in NEAR: return 'NEAR',NEAR[q]
    return 'OTHER',None
def fold(s): return re.sub(r"[^a-z]","",unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower())
def tline(v,h,race):
    v=np.asarray(v,float); h=np.asarray(h); n=len(v); n1=int((h==1).sum()); n2=n-n1
    m=v.mean() if n else np.nan; t=tstat(v) if n>2 else np.nan
    rs=pd.Series(v).groupby(np.asarray(race)).sum().values; tr=tstat(rs) if len(rs)>2 else np.nan
    h1=v[h==1].mean() if n1 else np.nan; h2=v[h==2].mean() if n2 else np.nan
    tg=np.nanmin([t,tr]) if n>2 else np.nan
    return dict(n=n,races=len(rs),per10=m,t=t,t_race=tr,h1=h1,h2=h2,n1=n1,n2=n2,PASS=bool(n>2 and passes(n,n1,n2,tg,h1,h2,m)))
# known answers, worked by hand
assert cls(2.0)==('ROUND',2.0) and cls(1.99)==('NEAR',2.0) and cls(2.02)==('NEAR',2.0) and cls(4.9)==('NEAR',5.0) and cls(21.0) is None and cls(2.04)==('OTHER',None)
assert abs(bk(5.0,True)-10*3.9*0.98)<1e-9 and bk(5.0,False)==-10.0 and abs(ly(5.0,False)-10/4.1*0.98)<1e-9 and ly(5.0,True)==-10.0
_l=tline([1.,3.,-1.,5.],[1,1,2,2],[1,1,2,3]); assert _l['n']==4 and _l['races']==3 and _l['h1']==2.0 and _l['h2']==2.0 and not _l['PASS']
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
cur.execute("SELECT event_dt,selection_name,win_lose FROM racing_bsp WHERE market='win' AND event_dt>='2024-08-30' AND bsp>1")
BS=defaultdict(list)
for dt,nm,w in cur.fetchall(): BS[(dt.date().isoformat(),fold(nm))].append((dt,w))
cur.execute("SELECT DISTINCT market_id,market_time FROM bf_hist_other WHERE sport='Horse Racing' AND market_type='WIN' AND country IN ('GB','IE')")
MK=sorted(cur.fetchall(),key=lambda r:r[1]); print(f"GB and IE WIN markets {len(MK)} | {time.time()-T0:.0f}s",flush=True)
SK=Counter(); R=[]; DONE=0
for c_ in range(0,len(MK),500):
    if time.time()-T0>BUDGET: SK['chunks not pulled, budget']+=1; break
    ids=[m[0] for m in MK[c_:c_+500]]; DONE+=len(ids)
    cur.execute("""SELECT market_id,extract(epoch from market_time)::float8,sel,extract(epoch from ts)::float8,ltp::float8 FROM bf_hist_other
                   WHERE sport='Horse Racing' AND market_id=ANY(%s) AND market_type='WIN' AND NOT inplay AND ts>=market_time-interval '5 minutes' AND ts<=market_time-interval '1 minute' AND ltp>=1.01 AND ltp<=1000""",(ids,))
    d=pd.DataFrame(cur.fetchall(),columns='m T sel ts p'.split())
    if d.empty: continue
    d=d.sort_values(['m','sel','ts'],kind='stable')
    tie=d.groupby(['m','sel','ts']).p.nunique(); amb=set((a,b) for a,b,_ in tie[tie>1].index)   # two prices at the same last second: skip that runner if it is the last
    for mk,G in d.groupby('m',sort=False):
        T=float(G['T'].iloc[0]); day=pd.Timestamp(T,unit='s',tz='UTC'); cand=[]
        for s,x in G.groupby('sel',sort=False):
            ts=x.ts.values; i=last_in(ts,T-5*M,T-1*M)
            if i is None: continue
            if (mk,s) in amb and (x.ts.values==ts[i]).sum()>1 and x.p[x.ts==ts[i]].nunique()>1: SK['runner tied last second']+=1; continue
            p=float(x.p.values[i]); c=cls(p)
            if c is None: continue
            cand.append((float(ts[i]),s,p,c))
        for kind in ('ROUND','NEAR','ALL'):
            cs=[c for c in cand if kind=='ALL' or c[3][0]==kind]
            if not cs: continue
            tt,s,p,c=max(cs,key=lambda z:z[0])
            rec=BS.get((day.date().isoformat(),fold(s)))
            if not rec: SK[f'{kind} no racing_bsp row']+=1; continue
            if len(rec)>1: SK[f'{kind} name twice that day']+=1; continue
            dt,w=rec[0]
            if abs((dt-day.tz_localize(None).to_pydatetime()).total_seconds())>2*3600+60: SK[f'{kind} event over 2 h away']+=1; continue
            if w is None: SK[f'{kind} win_lose null']+=1; continue
            won=bool(int(w)); R.append((kind,mk,T,s,p,c[1],won,bk(p,won),ly(p,won)))
    if (c_//500)%10==0: print(f"  {DONE}/{len(MK)} markets, rows {len(R)} | {time.time()-T0:.0f}s",flush=True)
con.close()
print(f"markets read {DONE} of {len(MK)}; counts {dict(sorted(SK.items()))}",flush=True)
D=pd.DataFrame(R,columns='kind m T sel p rnd won vb vl'.split())
if D.empty: print("ERROR: no runners, no verdict"); sys.exit(1)
print(f"bets {len(D)}, {pd.Timestamp(D['T'].min(),unit='s').date()} to {pd.Timestamp(D['T'].max(),unit='s').date()}\n",D.groupby('kind').size().to_string())
md=np.median(D['T'].values); D['h']=np.where(D['T'].values<=md,1,2)
def row(nm,x,side):
    x=x.dropna(subset=[side])
    if len(x)<3: return dict(line=nm,n=len(x))
    l=tline(x[side].values,x.h.values,x.m.values)
    return dict(line=nm)|{k:(round(v,3) if isinstance(v,float) else v) for k,v in l.items()}|dict(won=round(x.won.mean(),3),imp=round((1/x.p).mean(),3))
Rr=D[D.kind=='ROUND']
o=[row('WIN ROUND back *',Rr,'vb'),row('WIN ROUND lay *',Rr,'vl')]
r=[]
for k in ('NEAR','ALL'): r+=[row(f'WIN {k} back',D[D.kind==k],'vb'),row(f'WIN {k} lay',D[D.kind==k],'vl')]
for rv in ROUND:
    x=Rr[Rr.rnd==rv]
    if len(x)>=30: r+=[row(f'WIN ROUND {rv} back',x,'vb'),row(f'WIN ROUND {rv} lay',x,'vl')]
print("== ITEM 484, scored lines marked *\n",pd.DataFrame(o).to_string(index=False))
RR=pd.DataFrame(r); RR['PASS']=False
print("\n-- reading lines, cannot pass (by |t|)\n",RR.reindex(RR.t.abs().sort_values(ascending=False).index).to_string(index=False))
S=[s for s in o if s.get('PASS')]
print("\n== SURVIVORS"); print(pd.DataFrame(S).to_string(index=False) if S else "none",flush=True); print(f"total {time.time()-T0:.0f}s")
PY
