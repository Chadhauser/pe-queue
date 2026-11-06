#!/bin/bash
set -o pipefail
# 499_racing_layoff (Finder 2026-11-06, queue item 210, Finder's own, source b): days since last run at BSP, on complete run dates from the BASIC tape. Rule pushed before any price was read. The number 499 is reused: 450-499 are all taken.
# STATE from bf_hist_other Horse Racing WIN GB/IE: any runner name with a print in a market that day. A late non-runner with prints counts as a run: noise, not look-ahead. Only earlier dates are used. Names are matched exactly after folding case and spaces; two horses with one name share history.
# ENTRY BSP, one tick adverse, 2%, £10 risk, to result, nothing dropped; dead heats as jobs/499_race_shape.sh. Bands on ppwap, never BSP. ppwap runs to the off: a pass is an upper bound. racing_bsp holds about a fifth of the tape's races.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))  # this job only
import sys,time,re,bisect,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import LD,tstat,passes
from lib_wom import tgame
import lib_cand; lib_cand._checks()
pd.set_option('display.width',250); pd.set_option('display.max_rows',300); pd.set_option('display.max_columns',40)
T0=time.time()
def back_px(p):
    p=np.asarray(p,dtype=float); return LD[np.clip(np.searchsorted(LD,p-1e-9,side='left')-1,0,len(LD)-1)]
def lay_px(p):
    p=np.asarray(p,dtype=float); return LD[np.clip(np.searchsorted(LD,p+1e-9,side='right'),0,len(LD)-1)]
def pnl_back(a,wl):
    a=np.asarray(a,dtype=float); wl=np.asarray(wl); g=np.where(wl==1,10*(a-1),np.where(wl==2,5*(a-1)-5,-10.0))
    return np.where(g>0,g*.98,g)
def pnl_lay(a,wl):
    a=np.asarray(a,dtype=float); wl=np.asarray(wl); s=10/(a-1); g=np.where(wl==1,-10.0,np.where(wl==2,-5+s/2,s))
    return np.where(g>0,g*.98,g)
BANDS=[(0,3,'<=3'),(3,6,'3-6'),(6,12,'6-12'),(12,1e9,'12+')]
def band(p):
    p=np.asarray(p,dtype=float); o=np.empty(len(p),dtype=object)
    for lo,hi,n in BANDS: o[(p>lo)&(p<=hi)]=n
    return o
def fold(s): return re.sub(r'\s+',' ',str(s)).strip().lower()
def state(days):
    if days is None: return 'NEW'
    return 'Q7' if days<=7 else 'D14' if days<=14 else 'D30' if days<=30 else 'D90' if days<=90 else 'D180' if days<=180 else 'LONG'
def days_since(dates,d):
    """dates: sorted day numbers for a name. Days to the latest date strictly before d, else None."""
    i=bisect.bisect_left(dates,d)
    return None if i==0 else d-dates[i-1]
# known answers, worked by hand
assert [state(x) for x in (None,1,7,8,14,15,30,31,90,91,180,181)]==['NEW','Q7','Q7','D14','D14','D30','D30','D90','D90','D180','D180','LONG']
assert days_since([10,20,30],30)==10 and days_since([10,20,30],31)==1 and days_since([10],10) is None and days_since([],5) is None   # the same day never counts
assert fold(' Sizable  Sam ')=='sizable sam' and list(band([3,3.01,6,12,12.5]))==['<=3','3-6','3-6','6-12','12+']
assert back_px(11.2)==11.0 and lay_px(2.0)==2.02 and abs(pnl_back(3.0,1)-19.6)<1e-9 and abs(pnl_lay(3.0,0)-4.9)<1e-9 and pnl_lay(3.0,1)==-10 and pnl_lay(3.0,2)==-2.5
print("checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
cur.execute("SELECT DISTINCT sel,(market_time AT TIME ZONE 'UTC')::date FROM bf_hist_other WHERE sport='Horse Racing' AND market_type='WIN' AND country IN ('GB','IE')")
H={}
for s,d in cur.fetchall(): H.setdefault(fold(s),[]).append(d.toordinal())
for v in H.values(): v.sort()
print(f"names on the tape {len(H):,}, run dates {sum(len(v) for v in H.values()):,}, {time.time()-T0:.0f}s",flush=True)
R=pd.read_sql("SELECT event_id,event_name,event_dt,selection_id,selection_name,win_lose,bsp::float8 bsp,ppwap::float8 ppwap,pp_vol::float8 pp_vol FROM racing_bsp WHERE market='win' AND event_dt>='2025-03-01' AND event_dt<'2026-10-01'",con); con.close()
bad=R.bsp.isna()|(R.bsp<=1)|R.ppwap.isna()|(R.ppwap<=1)|R.pp_vol.isna()|R.win_lose.isna()
W=R[~R.event_id.isin(set(R.event_id[bad]))].copy(); bk=(1/W.ppwap).groupby(W.event_id).sum(); W=W[W.event_id.isin(bk[(bk>=1.0)&(bk<=1.40)].index)]
print(f"rows {len(R):,}; races kept {W.event_id.nunique():,}, runners {len(W):,}",flush=True)
dt=pd.to_datetime(W.event_dt); W['d']=[x.toordinal() for x in dt.dt.date]; W['ts']=dt.astype('int64')/1e9; W['nm']=W.selection_name.map(fold)
W['on_tape']=W.nm.isin(H); same=[d in set(H.get(n,())) for n,d in zip(W.nm.values[:20000],W.d.values[:20000])]
print(f"runner name on the tape at all {W.on_tape.mean():.3f}; on the tape that same day (first 20,000 runners) {np.mean(same):.3f}: a low figure means the name join is failing",flush=True)
W['st']=[state(days_since(H.get(n,[]),d)) for n,d in zip(W.nm,W.d)]; W['bd']=band(W.ppwap.values)
print("runners by state:",W.st.value_counts().to_dict(),flush=True)
W['vb']=pnl_back(back_px(W.bsp.values),W.win_lose.values); W['vl']=pnl_lay(lay_px(W.bsp.values),W.win_lose.values)
def tab(x,col,**k):
    v=x[col].values; md=np.median(x.ts.values); h=x.ts.values<md; a,b=v[h],v[~h]; t=tstat(v)
    return dict(**k,n=len(v),races=x.event_id.nunique(),per10=v.mean(),t=t,tr=tgame(v,x.event_id.values),n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,won=(x.win_lose==1).mean(),imp=(1/x.bsp).mean(),maxwin=v.max(),PASS=passes(len(v),len(a),len(b),t,a.mean() if len(a) else 0,b.mean() if len(b) else 0,v.mean()))
CTL={(bd,s):x[c].mean() for bd,x in W.groupby('bd') for s,c in (('back','vb'),('lay','vl'))}
out=[tab(x,c,st=st,band=bd,side=s,ctrl=CTL[(bd,s)]) for (st,bd),x in W.groupby(['st','bd']) for s,c in (('back','vb'),('lay','vl'))]
A=pd.DataFrame(out).sort_values('t',ascending=False); print(f"\n== ITEM 210 days since last run: {len(A)} lines, top 15 by t, then worst 3; ctrl = same band and side, all runners"); print(A.head(15).round(3).to_string(index=False)); print(A.tail(3).round(3).to_string(index=False))
print("\n-- by state, all bands, back, context:"); print(pd.DataFrame([tab(x,'vb',st=st) for st,x in W.groupby('st')]).drop(columns=['PASS']).round(3).to_string(index=False))
S=A[A.PASS==True]; print(f"\n== SURVIVORS: {len(S)}"); print(S.round(3).to_string(index=False) if len(S) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
