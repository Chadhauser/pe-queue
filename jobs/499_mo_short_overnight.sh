#!/bin/bash
set -o pipefail
# 499_mo_short_overnight (Finder 2026-11-06, queue item 281, from 499_open_vs_off): item 276's one pass, lay MO under 1.5 overnight, out at T-5, n 3,404 +0.997 t 5.94, h1 +0.330, h2 +1.547. Mean move +9% and a lay at a very short price carries a big stake, so a few junk prints could make all of it. Same entry and exit as 276; stress only. A crossing lay fills on an up-print (item 252). Read only. No tables written.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line,step,lay_hedge,tstat
from lib_official import fill,last_in,secs,checks
import lib_cand; lib_cand._checks(); checks()
# known answer: lay 1.2 -> 1.21, stake 10/0.21 = 47.619; out at 1.5, backing at 1.49: 47.619*(1-1.21/1.49) = 8.9485, less 2%
assert abs(lay_hedge(step(1.2,1),1.5)-(10/0.21)*(1-1.21/1.49)*.98)<1e-9
print("checks: OK",flush=True); T0=time.time()
pd.set_option('display.width',220); pd.set_option('display.max_columns',30)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
rows=[]; C=Counter()
for M0,M1 in zip(pd.date_range('2024-01-01','2026-10-01',freq='MS'),pd.date_range('2024-02-01','2026-11-01',freq='MS')):
    pr_=(M0.to_pydatetime(),M1.to_pydatetime())
    S=pd.read_sql("SELECT market_id,event_name ev,market_time mt,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type='MATCH_ODDS' AND market_time>=%s AND market_time<%s AND NOT inplay AND ltp>=1.01 AND ltp<1000 AND ((ts>=market_time-interval '72 hours' AND ts<=market_time-interval '12 hours') OR (ts>=market_time-interval '5 minutes' AND ts<=market_time-interval '1 minute'))",con,params=pr_)
    if not len(S): continue
    S['tt']=secs(S.ts); S['off']=secs(S.mt); S=S.sort_values('tt',kind='stable').drop_duplicates(['market_id','sel','tt'])
    for (m,s),y in S.groupby(['market_id','sel'],sort=False):
        o=float(y.off.iloc[0]); ts,px=y.tt.values,y.ltp.values
        i=last_in(ts,o-48*3600,o-12*3600)
        if i is None or not 1.01<=float(px[i])<1.5: continue
        j=last_in(ts,o-300,o-60)
        if j is None: C['no exit']+=1; continue
        q=float(px[j]); p=fill(ts,px,i,'L'); a=step(p,1); up=i>0 and px[i]>px[i-1]; hasprev=i>0
        # other prints of this runner in the entry window: is the entry print out of line with the median of the rest?
        w=px[(ts>=o-48*3600)&(ts<=o-12*3600)]; med=float(np.median(w)); nw=len(w)
        rows.append((m,y.ev.iloc[0],s,o,float(px[i]),a,q,lay_hedge(a,q),lay_hedge(step(p,3),q),up,hasprev,nw,float(px[i])/med-1,q>=2.0))
    del S
con.close(); print("counted",dict(C),f"{time.time()-T0:.0f}s",flush=True)
D=pd.DataFrame(rows,columns='m ev s off p a q v v3 up hp nw off_med flip'.split()); md=float(np.median(D.off)); print("trades",len(D),"split at",pd.Timestamp(md,unit='s',tz='UTC'))
out=[]
def add(nm,x,c='v'):
    if len(x)<30: out.append(dict(line=nm,n=len(x))); return
    l=line(x[c].astype(float).values,np.where(x.off<md,1,2)); out.append(dict(line=nm,n=l['n'],per10=l['per10'],t=l['t'],h1=l['h1'],h2=l['h2'],maxwin=l['maxwin'],PASS=l['PASS']))
add('276 as run',D); add('3 ticks adverse each way',D,'v3')
for lo,hi in ((1.01,1.1),(1.1,1.2),(1.2,1.35),(1.35,1.5)): add(f"print {lo}-{hi}",D[(D.p>=lo)&(D.p<hi)])
add('entry an up-print',D[D.up]); add('entry not an up-print',D[~D.up]); add('3+ prints in the window',D[D.nw>=3]); add('fewer than 3 prints',D[D.nw<3])
add('print within 5% of the window median',D[D.off_med.abs()<=.05]); add('print over 5% from the median',D[D.off_med.abs()>.05])
add('exit price under 2.0',D[~D.flip]); add('exit price 2.0 or more',D[D.flip])
srt=D.sort_values('v'); add('top 1% of wins removed',srt.iloc[:int(len(srt)*.99)]); add('top 5% of wins removed',srt.iloc[:int(len(srt)*.95)])
L=pd.DataFrame(out); print(L.round(3).to_string(index=False))
print("P&L percentiles p1 p25 p50 p75 p99:",D.v.quantile([.01,.25,.5,.75,.99]).round(3).tolist(),"share positive",round(float((D.v>0).mean()),3))
print("exit v entry, exit price percentiles p50 p90 p99:",D.q.quantile([.5,.9,.99]).round(3).tolist())
print("\nthe 12 biggest wins"); print(D.sort_values('v',ascending=False).head(12)[['ev','s','p','q','nw','v']].round(3).to_string(index=False))
print("\n== SURVIVORS: decided in the report, see the stress lines"); print(f"total {time.time()-T0:.0f}s")
PY
