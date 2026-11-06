#!/bin/bash
set -o pipefail
# 499_identity_touch (Finder 2026-11-06, queue item 300, Finder's own, source a; from jobs/499_dnb_touch.sh): item 293's identity pairs at the real touch on liq_sample, local copy. A pilot, no result read, it cannot pass; it asks whether the gap can be taken. Rule pushed in the queue before these prices. Read only.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(1_500_000_000,1_500_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_official import secs
pd.set_option('display.width',220); pd.set_option('display.max_columns',30)
def locked(b,l,S=10.0):
    """Back S at b on the event in one market, lay the same event at l in the other, lay stake S*b/l. Worst outcome after 2% on the winning leg (separate markets)."""
    L=S*b/l
    event=S*(b-1)*.98-L*(l-1)        # back leg wins, lay leg loses
    none=L*.98-S                      # lay leg wins, back leg loses
    return min(event,none)
def mid(b,l): return (b+l)/2
# known answers, worked by hand: back 3.0, lay 2.0: L 15; event 19.6-15 = 4.6; none 14.7-10 = 4.7; min 4.6.
assert abs(locked(3.0,2.0)-4.6)<1e-9
# Same price both sides: L 10; event 19.6-20 = -0.4 at 3.0; none 9.8-10 = -0.2; min -0.4, commission alone loses.
assert abs(locked(3.0,3.0)+0.4)<1e-9
assert mid(2.0,2.04)==2.02
print("checks: OK",flush=True); T0=time.time()
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
PAIRS=[('FH05 v HT_CS','FH05','UNDER 0.5 GOALS','HT_CS'),('OU05 v CS','OU05','UNDER 0.5 GOALS','CS')]
F=pd.read_sql("SELECT event_name ev,min(ts) t1 FROM liq_sample WHERE mkt='MO' AND minute>=1 GROUP BY 1",con); F['t1s']=secs(F.t1); FIRST=dict(zip(F.ev,F.t1s))
for name,a,us,b in PAIRS:
    P=pd.read_sql("SELECT DISTINCT ts,event_name ev,mkt,sel,back_px::float8 b,lay_px::float8 l,back_sz::float8 bs,lay_sz::float8 ls FROM liq_sample WHERE mkt=ANY(%s) AND minute=0 AND back_px>=1.01 AND lay_px>back_px AND lay_px<1000",con,params=([a,b],))
    print(name,"labels on the score leg",sorted(P[P.mkt==b].sel.unique())[:8],flush=True)
    zero=[s for s in P[P.mkt==b].sel.unique() if s.replace(' ','') in ('0-0',)]
    if not zero: print(" no 0-0 label, stop this pair"); continue
    P=P[((P.mkt==a)&(P.sel==us))|((P.mkt==b)&(P.sel==zero[0]))]; P['tt']=secs(P.ts); C=Counter(); R=[]
    for ev,g in P.groupby('ev',sort=False):
        t1=FIRST.get(ev)
        if t1 is None: C['no in-play row']+=1; continue
        g=g[g.tt<=t1-120]; x=g[g.mkt==a].sort_values('tt'); y=g[g.mkt==b].sort_values('tt')
        if not len(x) or not len(y): C['a leg has no row']+=1; continue
        u=x.iloc[-1]; z=y.iloc[-1]
        if abs(u.tt-z.tt)>120: C['rows over 120 s apart']+=1; continue
        gp=100*(1/mid(u.b,u.l)-1/mid(z.b,z.l))
        l1=locked(u.b,z.l); l2=locked(z.b,u.l)   # back Under, lay 0-0; back 0-0, lay Under
        R.append(dict(ev=ev,mid_gap=gp,sp_u=100*(1/u.b-1/u.l),sp_z=100*(1/z.b-1/z.l),l1=l1,l2=l2,best=max(l1,l2),sz1=min(u.bs,z.ls),sz2=min(z.bs,u.ls))); C['read']+=1
    print(" counts",dict(C),flush=True)
    if not R: continue
    D=pd.DataFrame(R); print(f" games {len(D)}; median spread, points: Under {D.sp_u.median():.2f}, 0-0 {D.sp_z.median():.2f}; mid gap mean {D.mid_gap.mean():+.2f} median {D.mid_gap.median():+.2f} sd {D.mid_gap.std():.2f}")
    print(f" mid gap Under cheap by 2+ {int((D.mid_gap<=-2).sum())}; dear by 2+ {int((D.mid_gap>=2).sum())}")
    print(f" locked per £10 backed: best way round median {D.best.median():+.3f}, max {D.best.max():+.3f}; games with a locked profit {int((D.best>0).sum())}")
    W=D[D.best>0]
    if len(W): print(W.assign(size=np.where(W.l1>=W.l2,W.sz1,W.sz2))[['ev','mid_gap','best','size']].sort_values('best',ascending=False).head(10).round(3).to_string(index=False))
con.close()
print("SURVIVORS: pilot, no result read, none",flush=True)
PY
