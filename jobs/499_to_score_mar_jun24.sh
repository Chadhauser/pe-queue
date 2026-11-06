#!/bin/bash
set -o pipefail
# 499_to_score_mar_jun24 (Finder 2026-11-06, queue item 259, Finder's own, source c; from jobs/499_to_score_all_oct24.sh, jobs/499_scorer_form.sh): is item 251's lay tilt there on months that chose nothing? Rule pushed in the queue (7bf813f) before any Mar-Jun 2024 TO_SCORE price was read. Read only.
# RULE first non-in-play print T-30 to the off, every runner, lay at the worse of it and the next within 120 s, one tick adverse, 2%, £10 liability, to WINNER or LOSER, any other status void, counted. Scored: fill in 10-200. Diagnostics, cannot pass: entry print above the print before it, from T-60; and item 251's first up-print in T-30 to the off, one tick.
# Many runners a game: tg, t on per-game sums, must also reach 3.5. Thin prints: a pass supports the tilt only. No model here, so this does not clear item 251.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_000_000_000,2_000_000_000))  # this job only
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import tstat,line,step
from lib_official import ly,secs,first_in,fill,checks
import lib_cand; lib_cand._checks(); checks()
def up_print(ts,px,off):
    """As jobs/499_scorer_form.sh: first print in T-30 to the off above the runner's previous print."""
    for i in range(1,len(ts)):
        if off-1800<=ts[i]<=off and px[i]>px[i-1]: return float(px[i])
    return None
# known answers: lay 6.0 -> 6.2: stake 10/5.2 = 1.923, wins 1.8846, loses -10.
assert abs(ly(6.0,False)-1.884615)<1e-5 and ly(6.0,True)==-10.0
_t=np.array([100.,800.,860.]); _p=np.array([9.,6.,6.4]); _i=first_in(_t,200.,2000.); assert _i==1 and fill(_t,_p,_i,'L')==6.4
assert up_print(np.array([100.,800.,900.,950.]),np.array([9.,8.,10.,12.]),2000.)==10.0 and up_print(np.array([800.,900.]),np.array([9.,8.]),2000.) is None
assert secs(pd.Series(pd.to_datetime(['2026-01-01 00:00:00+00:00']))).iloc[0]==1767225600.0
print("checks: OK",flush=True); T0=time.time()
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
P=pd.read_sql("SELECT market_id,event_id,market_time mt,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type='TO_SCORE' AND market_time>='2024-03-01' AND market_time<'2024-07-01' AND NOT inplay AND ltp>=1.01 AND ltp<1000 AND ts>=market_time-interval '60 minutes'",con)
if P.empty: print("no TO_SCORE markets on Mar-Jun 2024\n\n== SURVIVORS: none (BLOCKED, no data)"); sys.exit(0)
RS=pd.read_sql("SELECT market_id,sel,status FROM bf_hist_result WHERE sport='Soccer' AND market_type='TO_SCORE' AND market_id=ANY(%s)",con,params=(list(P.market_id.unique()),)); con.close()
P['mon']=pd.to_datetime(P.mt,utc=True).dt.strftime('%Y-%m')
print(f"prints {len(P):,}, markets {P.market_id.nunique()}, events {P.event_id.nunique()}, by month {P.groupby('mon').event_id.nunique().to_dict()}; result rows {len(RS)}, markets with results {RS.market_id.nunique()}; statuses {RS.status.value_counts().to_dict()}",flush=True)
ST={(a,b):c for a,b,c in zip(RS.market_id,RS.sel,RS.status)}; P['tt']=secs(P.ts); P['off']=secs(P.mt); P=P.drop_duplicates(['market_id','sel','tt']).sort_values('tt',kind='stable')
C=Counter(); rows=[]
for (m,s),y in P.groupby(['market_id','sel'],sort=False):
    st=ST.get((m,s))
    if st is None: C['no result row']+=1; continue
    if st not in ('WINNER','LOSER'): C['void: '+str(st)]+=1; continue
    ts,px=y.tt.values,y.ltp.values; o=float(y.off.iloc[0]); i=first_in(ts,o-1800,o)
    if i is None: C['no print in window']+=1; continue
    p=fill(ts,px,i,'L')
    if p>200: C['over 200']+=1; continue
    won=st=='WINNER'; up=bool(i>0 and px[i]>px[i-1]); u=up_print(ts,px,o)
    rows.append((y.event_id.iloc[0],o,y.mon.iloc[0],s,p,won,ly(p,won),up,(ly(u,won) if u is not None and u<=200 else np.nan)))
print("counted:",dict(sorted(C.items())),flush=True)
R=pd.DataFrame(rows,columns='e off mon sel p won v up vu'.split())
if R.empty: print("\n== SURVIVORS: none (no trades)"); sys.exit(0)
md=R.groupby('e').off.first().median()
def show(name,x,col='v'):
    x=x[x[col].notna()]
    if not len(x): print(f"{name}: n 0"); return None,0.0
    v=x[col].values.astype(float); l=line(v,np.where(x.off<=md,1,2)); tg=tstat(x.groupby('e')[col].sum().values)
    print(f"{name}: n {l['n']} games {x.e.nunique()} per10 {l['per10']:+.3f} t {l['t']:.2f} tg {tg:.2f} h1 {l['h1']:+.3f} (n {l['n1']}) h2 {l['h2']:+.3f} (n {l['n2']}) won {x.won.mean():.3f} implied {(1/x.p.map(lambda q:step(q,1))).mean():.3f} maxwin {l['maxwin']:.2f}",flush=True)
    return l,tg
B=R[(R.p>=10)&(R.p<=200)]
L,TG=show("259 TO_SCORE 10-200 lay, THE SCORED LINE",B)
show("  diagnostic, entry print is an up-print",B[B.up])
show("  diagnostic, item 251's first up-print, one tick",B,'vu')
for k,y in B.groupby('mon'): show(f"  month {k}",y)
for lo,hi in ((1,4),(4,10),(10,20),(20,50),(50,200.01)):
    show(f"  context fill {lo}-{hi:.0f}",R[(R.p>=lo)&(R.p<hi)])
show("  context ALL lay",R)
print("\n== SURVIVORS (standard bar and tg >= 3.5)"); print("259 PASS" if L and L['PASS'] and TG>=3.5 else "none"); print(f"done {time.time()-T0:.0f}s")
PY
