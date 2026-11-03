#!/bin/bash
set -o pipefail
# 459 (Finder 2026-11-03, queue item 10): WEIGHT OF MONEY ON THE STREAM (Webb/Howe). stream_ticks, PRE-OFF only (inplay=false, OPEN),
# football MO (MO_PRE on this table) and racing WIN, over the WHOLE table range (stream_ticks keeps ~3.7 days; printed). Imbalance = back_sz/(back_sz+lay_sz) at the touch (back_sz = size available to back, i.e. offered by layers;
# item's definition), averaged over the ticks of the last 60 s for that selection. Trigger: imbalance >= 0.7 (and, mirror, <= 0.3),
# one trigger per selection per 180 s (non-overlapping), entry needs secs_to_off >= 240 so the 180 s exit is still pre-off.
# Outcome: book state at t+60/t+180 = the latest tick at or before that time (the stream sends deltas only, so this IS the standing book),
# required to be <= 120 s old, else counted and settled as "no exit" (not dropped silently). Move in ladder ticks of back_px (+ = shortened).
# Trade: back at back_px -1 tick, exit (lay) at lay_px +1 tick after 180 s; 2% commission on profit; £10 stake. Halves = before/after
# the median trigger time. Correlated: many selections per market and many triggers per selection; the markets count is reported.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,os,time,psycopg2,pandas as pd,numpy as np
from collections import defaultdict
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
LAD=[]; p=1.01
for lo,hi,st in ((1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)):
    x=lo
    while x<hi-1e-9: LAD.append(round(x,2)); x+=st
LAD.append(1000.0); LAD=np.array(LAD)
def ti(p): return int(np.searchsorted(LAD,round(p,2)-1e-9))
def tick(p): return 0.01 if p<2 else 0.02 if p<3 else 0.05 if p<4 else 0.1 if p<6 else 0.2 if p<10 else 0.5 if p<20 else 1 if p<30 else 2 if p<50 else 5 if p<100 else 10
def pnl(p,q):
    p=p-tick(p)
    if p<=1.01: return None
    q=q+tick(q); r=10*(p/q-1); return r*0.98 if r>0 else r
assert ti(2.0)-ti(1.99)==1 and ti(3.0)-ti(2.0)==50 and ti(1.01)==0 and abs(pnl(3.05,2.98)-10*(3.0/3.0-1))<1e-9
assert abs(pnl(4.1,3.0)-10*(4.0/3.05-1)*0.98)<1e-9
print("ladder + P&L unit checks: OK",flush=True)
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor(); cur.execute("SET statement_timeout='1800s'")
cur.execute("SELECT min(ts_recv), max(ts_recv) FROM stream_ticks"); r=cur.fetchone(); print("stream_ticks range:",r[0],"..",r[1],flush=True)
# v2: run 1 found no rows (names on this table are racing/WIN and football/MO_PRE); the whole table (3.7 days) fits, so no day cut
D=pd.Timestamp(r[0]); D1=pd.Timestamp(r[1])+pd.Timedelta(seconds=1); t0=time.time()
M=pd.read_sql("""SELECT sport, mkt, count(*) n, count(DISTINCT market_id) markets FROM stream_ticks WHERE ts_recv>=%s AND ts_recv<%s AND inplay=false
  GROUP BY 1,2 ORDER BY 3 DESC""",con,params=(D,D1))
print(f"sample {D} .. {D1} pre-off ticks by sport/mkt ({int(time.time()-t0)}s):\n",M.head(15).to_string(index=False),flush=True)
keep=[(s,m) for s,m in zip(M.sport,M.mkt) if (s=='football' and m in ('MO','MO_PRE')) or (s.lower() in ('racing','horse_racing') and m.upper()=='WIN')]
print("tested:",keep,flush=True)
rows=[]; SK=defaultdict(int)
for sport,mkt in keep:
    T=pd.read_sql("""SELECT market_id, sel_id, ts_recv ts, back_px::float bp, back_sz::float bs, lay_px::float lp, lay_sz::float ls, secs_to_off
      FROM stream_ticks WHERE ts_recv>=%s AND ts_recv<%s AND inplay=false AND status='OPEN' AND sport=%s AND mkt=%s
      ORDER BY market_id, sel_id, ts_recv""",con,params=(D,D1,sport,mkt))
    print(f"  {sport}/{mkt}: {len(T)} ticks, {T.market_id.nunique()} markets ({int(time.time()-t0)}s)",flush=True)
    T=T[(T.bp>1)&(T.lp>1)&(T.bs>0)&(T.ls>0)&(T.bp<=50)]
    for (mid,sid),g in T.groupby(['market_id','sel_id'],sort=False):
        if len(g)<10: continue
        ts=g.ts.values; im=(g.bs/(g.bs+g.ls)).values
        roll=pd.Series(im,index=g.ts).rolling('60s').mean().values
        bp=g.bp.values; lp=g.lp.values; sto=g.secs_to_off.astype(float).values
        nxt_ok=ts[0]-np.timedelta64(1,'s')
        cand=np.where(((roll>=0.7)|(roll<=0.3))&(sto>=240)&((ts-ts[0])>=np.timedelta64(60,'s')))[0]
        for i in cand:
            if ts[i]<nxt_ok: continue
            sig='>=0.7' if roll[i]>=0.7 else '<=0.3'
            nxt_ok=ts[i]+np.timedelta64(180,'s')
            out={}
            for h in (60,180):
                j=np.searchsorted(ts,ts[i]+np.timedelta64(h,'s'),side='right')-1
                out[h]=None if (ts[i]+np.timedelta64(h,'s')-ts[j])>np.timedelta64(120,'s') else j
            if out[180] is None: SK[f'{sport} {sig}: exit book >120 s old']+=1; continue
            j6,j18=out[60],out[180]
            r=pnl(bp[i],lp[j18])
            if r is None: SK['unfillable 1.01']+=1; continue
            b=bp[i]; band='<2' if b<2 else '2-4' if b<4 else '4-10' if b<10 else '10-50'
            rows.append(dict(sport=sport,sig=sig,band=band,mid=mid,ts=ts[i],
                 mv60=(ti(bp[i])-ti(bp[j6])) if j6 is not None else np.nan, mv180=ti(bp[i])-ti(bp[j18]), pnl=r))
R=pd.DataFrame(rows); print("skips (counted):",dict(SK),flush=True)
if R.empty: print("\n== SURVIVORS: 0\nnone (no triggers)"); sys.exit()
med=R.ts.median(); R['half']=np.where(R.ts<med,'H1','H2'); print("half split at",med)
def tstat(x): x=x.dropna(); return x.mean()/(x.std(ddof=1)/len(x)**0.5) if len(x)>1 and x.std(ddof=1)>0 else 0.0
out=[]
for dims in (['sport','sig'],['sport','sig','band']):
    for k,gg in R.groupby(dims):
        a=gg[gg.half=='H1'].pnl; b=gg[gg.half=='H2'].pnl
        out.append(dict(cell=' / '.join(map(str,k)),n=len(gg),markets=gg.mid.nunique(),
            short60=(gg.mv60>0).mean(),long60=(gg.mv60<0).mean(),mv60=gg.mv60.mean(),short180=(gg.mv180>0).mean(),long180=(gg.mv180<0).mean(),mv180=gg.mv180.mean(),
            per10=gg.pnl.mean(),t=tstat(gg.pnl),n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan))
S=pd.DataFrame(out).round(3)
S['PASS']=(S.n>=300)&(S.n1>=150)&(S.n2>=150)&(S.t>=3.5)&(S.h1>0)&(S.h2>0)&(S.per10>=0.15)
pd.set_option('display.width',260); pd.set_option('display.max_rows',100)
print("\n== hit rates (share of triggers where back_px shortened / lengthened), mean move in ticks (+ = shortened), P&L per £10")
print(S.to_string(index=False))
print("\n== top 15 by t"); print(S.sort_values('t',ascending=False).head(15).to_string(index=False))
W=S[S.PASS].sort_values('t',ascending=False)
print(f"\n== SURVIVORS: {len(W)}"); print(W.to_string(index=False) if len(W) else "none")
PY
