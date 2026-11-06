#!/bin/bash
set -o pipefail
# 499_greyhound_bounce (Finder 2026-11-06, queue item 252; Finder's own, source a; from jobs/499_greyhound_am_green.sh): is item 247's drift bid-ask bounce? Rule pushed in the queue before any price was read. Read only.
# CORRECTION to the rule pushed in the queue, made after the first run: that rule had the sides reversed. A crossing lay fills at the lowest price on offer to lay, the HIGH side, printing an up-tick; a crossing back fills at the highest on offer to back, the LOW side, printing a down-tick (lib_cand agrees: a lay's adverse tick is up).
# CROSS lay at the last up-print 5 to 20 min out, back at the last down-print under 5 min out: what a taker pays, the line that can pass. REST lay at the last down-print, back at the last up-print: both legs resting and filled, no queue, no adverse selection and the last print of each window picked in hindsight, so REST can never pass.
# One tick adverse each way on both, and the same without it (per10_0): a directional print is already at the far side, so the extra tick charges the spread twice on CROSS. 2%, £10 liability. No result read. No exit counted: over 10% cannot pass.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(3_500_000_000,3_500_000_000))  # this job only
import sys,time,warnings,psycopg2,pandas as pd,numpy as np
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,line,lay_hedge,tstat
pd.set_option('display.width',230); pd.set_option('display.max_rows',150); pd.set_option('display.max_columns',30)
T0=time.time()
def green(x,q): return lay_hedge(step(x,1),q)
def green0(x,q):
    """As green, no extra tick: laid at x, out by backing at q, 2% on a profit."""
    v=(10/(x-1))*(1-x/q); return v*0.98 if v>0 else v
def picks(x):
    """x: one month's prints sorted by market, runner, time, with mins to the off. Previous print is taken over every pre-off print, then the windows are applied. Returns E (last down and up print 5-20 min) and Q (under 5)."""
    x=x.copy(); pv=x.groupby(['market_id','sel'],sort=False).ltp.shift(1); x['dir']=np.where(pv.isna()|(x.ltp==pv),0,np.where(x.ltp<pv,-1,1))
    x=x[(x.mins>=0)&(x.mins<=20)&(x.dir!=0)]
    out={}
    for nm,w in (('E',x[x.mins>=5]),('Q',x[x.mins<5])):
        for d,lab in ((-1,'dn'),(1,'up')):
            out[nm+lab]=w[w.dir==d].groupby(['market_id','sel'],sort=False).tail(1)[['market_id','sel','ltp']].rename(columns={'ltp':nm+lab})
    return out
# known answers, worked by hand
_x=pd.DataFrame(dict(market_id=['m']*6,sel=['a']*6,mins=[25.,15.,10.,4.,3.,2.],ltp=[4.0,3.8,4.2,4.1,4.5,4.4]))
_p=picks(_x)
assert float(_p['Edn'].Edn.iloc[0])==3.8 and float(_p['Eup'].Eup.iloc[0])==4.2 and float(_p['Qup'].Qup.iloc[0])==4.5 and float(_p['Qdn'].Qdn.iloc[0])==4.4
_y=pd.DataFrame(dict(market_id=['m']*2,sel=['a']*2,mins=[10.,2.],ltp=[4.0,4.0])); _q=picks(_y); assert len(_q['Edn'])==0 and len(_q['Qup'])==0   # a first print and an unchanged print have no direction
assert abs(green(3.0,5.0)-1.804878)<1e-5 and abs(green(3.0,2.0)+2.598358)<1e-5
# lay 3.0 stake 5; out at 4.0: 5*(1-3/4) = 1.25, less 2% = 1.225; out at 2.0: 5*(1-3/2) = -2.5; unchanged 0
assert abs(green0(3.0,4.0)-1.225)<1e-9 and abs(green0(3.0,2.0)+2.5)<1e-9 and green0(3.0,3.0)==0
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
rows=[]; mons=pd.date_range('2024-09-01','2026-11-01',freq='MS')
for a,b in zip(mons[:-1],mons[1:]):
    cur.execute("""SELECT market_id,market_time,sel,ts,ltp::float8 FROM bf_hist_other WHERE sport='Greyhound Racing' AND market_type='WIN' AND NOT inplay AND ltp>=1.01 AND ltp<1000 AND market_time>=%s AND market_time<%s""",(a.date(),b.date()))
    x=pd.DataFrame(cur.fetchall(),columns='market_id market_time sel ts ltp'.split())
    if not len(x): continue
    x['mt']=pd.to_datetime(x.market_time,utc=True); x['t']=pd.to_datetime(x.ts,utc=True); x['mins']=(x.mt-x.t)/pd.Timedelta(minutes=1)
    M=x.drop_duplicates('market_id')[['market_id','mt']]; x=x[x.mins>=0].sort_values(['market_id','sel','t'],kind='stable'); p=picks(x); del x
    E=p['Edn'].merge(p['Eup'],on=['market_id','sel'],how='outer').merge(p['Qdn'],on=['market_id','sel'],how='left').merge(p['Qup'],on=['market_id','sel'],how='left').merge(M,on='market_id')
    rows.append(E); print(f"  {a.date()} markets {len(M)} entries {len(E)} | {time.time()-T0:.0f}s",flush=True)
con.close()
R=pd.concat(rows,ignore_index=True); del rows
R['hr']=R.mt.dt.tz_convert('Europe/London').dt.hour; R['AM']=R.hr<13; R['era']=np.where(R.mt<pd.Timestamp('2026-05-01',tz='UTC'),'UNSEEN','CHOSEN'); R['when']=R.mt.astype('int64')
out=[]
for mode,ec,qc in (('CROSS','Eup','Qdn'),('REST','Edn','Qup')):
    A=R[R[ec].notna()&(R[ec]>=3)&(R[ec]<6)].copy(); A['v']=[green(a,b) if b==b else np.nan for a,b in zip(A[ec],A[qc])]; A['v0']=[green0(a,b) if b==b else np.nan for a,b in zip(A[ec],A[qc])]; A['move']=1/A[ec]-1/A[qc]
    for era in ('UNSEEN','CHOSEN'):
        for nm,S in (('AM 3-6',A[(A.era==era)&A.AM]),('REST 3-6',A[(A.era==era)&~A.AM])):
            x=S.dropna(subset=['v']); md=np.median(x.when.values); l=line(x.v.values,np.where(x.when.values<md,1,2)); tr=tstat(x.groupby('market_id').v.sum().values); noex=S.v.isna().mean()
            out.append(dict(mode=mode,era=era,line=nm,n=l['n'],races=x.market_id.nunique(),per10=round(l['per10'],3),per10_0=round(x.v0.mean(),3),t=round(l['t'],2),t_race=round(tr,2),h1=round(l['h1'],3),h2=round(l['h2'],3),noexit=round(noex,4),move=round(x.move.mean(),4),PASS=bool(mode=='CROSS' and era=='UNSEEN' and l['PASS'] and tr>=3.5 and noex<=0.10)))
T=pd.DataFrame(out); print("\n== LINES\n",T.to_string(index=False))
print("\nSURVIVORS"); S=T[T.PASS]; print(S.to_string(index=False) if len(S) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
