#!/bin/bash
set -o pipefail
# 494 (Finder 2026-11-04, queue item 41): REST INSIDE THE GAP on wide pre-match books. stream_ticks football MO_PRE, pre-off, OPEN, whole rolling table (range printed). PILOT.
# ANCHOR as job 485: last tick at or before T-115 min, no older than 300 s, on all three runners. SIGNAL: overround (sum 1/back_px) >= 103; CTRL < 103, same rule. Runner = widest gap in ladder ticks, gap >= 2 (a 1-tick book has no inside), counted.
# ORDERS, both sides, one market = one signal per side, never netted: RLAY offers the lay at back_px +1 tick (a backer takes it). RBACK offers the back at lay_px -1 tick (a layer takes it).
# FILL (strict, as job 492): a fresh print (runner's traded volume up on the previous tick; a stale ltp is not a print) strictly THROUGH X: below X for RLAY, above X for RBACK. Nothing at X counts, so queue position is never assumed.
# LIVE: to T-5, cancelled there. CANCEL variant (for reading): also cancelled at the first 1-tick book, as the gap the order was sitting in has gone. Unfilled = £0, reported.
# EXIT after a fill: the first later tick with a 1-tick book, else the last tick at or before T-5, else the fill tick's own book; cross the opposite touch. Pre-off positions do not settle, nothing to settle at result.
# COST: per10 = one tick adverse at entry and exit (house rule, and it is what PASS reads). at_level enters at exactly X, diagnostic. £10 risk: back stake £10, lay liability £10. 2% commission on profit.
# One trade per market per side, so t is not inflated by repeat entries. Halves: median signal time of the OR>=103 markets. per_sig = per10 x fill rate. mv_f / mv_u = log mid move, signal to exit time T-5, filled v unfilled, > 0 = shortened.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,warnings,psycopg2,pandas as pd,numpy as np
from collections import Counter
warnings.filterwarnings('ignore')
pd.set_option('display.width',240); pd.set_option('display.max_rows',120); pd.set_option('display.max_columns',30)
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
LAD=[]
for lo,hi,st in ((1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)):
    x=lo
    while x<hi-1e-9: LAD.append(round(x,2)); x+=st
LAD.append(1000.0); LAD=np.array(LAD)
def ix(p): return int(np.searchsorted(LAD,round(float(p),2)-1e-9))
def dn(p): return float(LAD[max(ix(p)-1,0)])
def up(p): return float(LAD[min(ix(p)+1,len(LAD)-1)])
def gap(b,l): return ix(l)-ix(b)
def comm(x): return x*0.98 if x>0 else x
def back_pnl(entry,lp1): return comm(10*(entry/up(lp1)-1))                       # back stake £10 at entry, lay out one tick above the lay touch
def lay_pnl(entry,bp1): return comm(10/(entry-1)*(1-entry/max(1.01,dn(bp1))))    # lay liability £10 at entry, back out one tick below the back touch
def rback_pnl(x,lp1): return back_pnl(dn(x),lp1)                                 # one tick adverse: a back fills shorter
def rlay_pnl(x,bp1): return lay_pnl(up(x),bp1)                                   # one tick adverse: a lay fills longer
def anchor(sto,x,maxage=300):
    idx=np.where(sto>=x)[0]
    if len(idx)==0: return None
    i=idx[-1]
    return int(i) if sto[i]-x<=maxage else None
def overround(backs): return 100*sum(1/b for b in backs)
def fill_at(side,sto,bp,lp,ltp,tv,i,x0,tlast=300,cancel=False):
    """First j > i at or before T-5 with a fresh print strictly through x0. None if never, or if cancel and a 1-tick book came first (a print on that same tick does not fill)."""
    for j in range(i+1,len(sto)):
        if sto[j]<tlast: return None
        if cancel and gap(bp[j],lp[j])==1: return None
        if not tv[j]>tv[j-1] or not np.isfinite(ltp[j]): continue
        if (side=='RLAY' and ltp[j]<x0-1e-9) or (side=='RBACK' and ltp[j]>x0+1e-9): return j
    return None
def exit_index(sto,bp,lp,j,tlast=300):
    """first tick after the fill with a 1-tick book at or before T-5, else last tick at or before T-5, else the fill tick"""
    last=None
    for k in range(j+1,len(sto)):
        if sto[k]<tlast: break
        last=k
        if gap(bp[k],lp[k])==1: return k,'closed'
    return (last,'T-5') if last is not None else (j,'no_later')
def pband(p): return '<2' if p<2 else '2-3' if p<3 else '3-5' if p<5 else '5-10' if p<10 else '10+'
def tstat(v):
    v=np.asarray(v,dtype=float)
    if len(v)<2: return 0.0
    s=v.std(ddof=1); return float(v.mean()/(s/len(v)**0.5)) if s>0 else 0.0
# known answers, worked by hand
assert gap(2.0,2.02)==1 and gap(2.0,2.06)==3 and dn(2.06)==2.04 and up(2.0)==2.02
assert abs(overround([2.0,4.0,4.0])-100.0)<1e-9
assert abs(rback_pnl(2.04,2.0)-10*(2.02/2.02-1))<1e-9                            # back fills 2.02, lay out at 2.0+1 tick = 2.02: exactly level, no commission
assert abs(rback_pnl(3.0,2.5)-0.98*10*(2.98/2.52-1))<1e-9                        # price shortened: profit, 2% off
assert abs(rlay_pnl(2.02,2.0)-10/(2.04-1)*(1-2.04/1.99))<1e-9                    # lay fills 2.04, back out 1.99: a loss, no commission
assert abs(rlay_pnl(5.0,6.0)-0.324101)<1e-6                                      # job 469's answer: lay 5.0 fills 5.1, out at 5.9
_s=np.array([6900.,6000.,5000.,4000.,200.]); _b=np.array([2.0,2.0,2.0,2.0,2.0]); _l=np.array([2.1,2.1,2.1,2.1,2.1]); _v=np.array([10.,20,30,40,50])
assert fill_at('RBACK',_s,_b,_l,np.array([2.0,2.08,2.1,2.1,2.1]),_v,0,2.08)==2   # 2.08 is at X, no fill; 2.10 is through
assert fill_at('RLAY',_s,_b,_l,np.array([2.1,2.02,1.99,1.99,1.99]),_v,0,2.02)==2 # 2.02 is at X, no fill; 1.99 is through
assert fill_at('RLAY',_s,_b,_l,np.array([2.1,2.1,2.1,2.1,1.99]),_v,0,2.02) is None   # through only on the tick past T-5: order already cancelled
assert fill_at('RBACK',_s,_b,_l,np.array([2.0,2.1,2.1,2.1,2.1]),np.array([10.,10,10,10,10]),0,2.08) is None   # above X with flat volume: stale, not a print
_l3=np.array([2.1,2.02,2.1,2.1,2.1])                                             # book closes to 1 tick at index 1
assert fill_at('RBACK',_s,_b,_l3,np.array([2.0,2.0,2.1,2.1,2.1]),_v,0,2.08)==2 and fill_at('RBACK',_s,_b,_l3,np.array([2.0,2.0,2.1,2.1,2.1]),_v,0,2.08,cancel=True) is None
assert exit_index(_s,_b,_l3,0)==(1,'closed') and exit_index(_s,_b,_l,0)==(3,'T-5') and exit_index(_s,_b,_l,3)==(3,'no_later')
assert anchor(np.array([7100.,6950.,6800.]),6900)==1 and anchor(np.array([7300.]),6900) is None
assert pband(1.99)=='<2' and pband(10.0)=='10+' and abs(tstat([1,3])-2.0)<1e-9
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)

con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'; SET max_parallel_workers_per_gather=0")
t0=time.time()
cur.execute("SELECT min(ts_recv),max(ts_recv) FROM stream_ticks"); r=cur.fetchone(); print("stream_ticks range:",r[0],"..",r[1],flush=True)
parts=[]
for a in pd.date_range(pd.Timestamp(r[0]).floor('6h'),pd.Timestamp(r[1]),freq='6h'):
    cur.execute("""SELECT market_id,sel,extract(epoch from ts_recv)::float8,secs_to_off::float4,back_px::float4,lay_px::float4,ltp::float4,tv::float8
      FROM stream_ticks WHERE ts_recv>=%s AND ts_recv<%s AND sport='football' AND mkt='MO_PRE' AND inplay=false AND status='OPEN' AND secs_to_off>=0""",(a,a+pd.Timedelta(hours=6)))
    d=pd.DataFrame(cur.fetchall(),columns=['mid','sel','ts','sto','bp','lp','ltp','tv']); parts.append(d)
    print(f"  chunk {a}: {len(d)} ticks ({int(time.time()-t0)}s)",flush=True)
con.close()
T=pd.concat(parts,ignore_index=True); n_all=len(T)
T=T.dropna(subset=['bp','lp','sto'])
for c in ('bp','lp','ltp'): T[c]=T[c].astype(float).round(2)
T=T[(T.bp>1)&(T.lp>T.bp)&(T.lp<1000)].sort_values(['mid','sel','ts'],kind='stable')
print(f"ticks {n_all}, usable touch {len(T)}, markets {T.mid.nunique()}, ltp null {T.ltp.isna().mean():.1%}, tv null or zero {((T.tv.isna())|(T.tv<=0)).mean():.1%}",flush=True)
_f=T.groupby(['mid','sel']).tv.max().groupby('mid').nunique(); print(f"tv is per runner: {(_f>1).mean():.1%} of markets have runners with different final tv",flush=True)
SK=Counter(); rows=[]; ANCH=115*60
for mid_,g in T.groupby('mid',sort=False):
    if g.sel.nunique()!=3: SK['market not 3-way']+=1; continue
    R={}
    for name,s in g.groupby('sel'):
        R[name]=(s.sto.values.astype(float),s.bp.values,s.lp.values,s.ltp.values,pd.Series(s.tv.values).where(lambda z:z>0).ffill().values,s.ts.values)
    A={n:anchor(v[0],ANCH) for n,v in R.items()}
    if any(i is None for i in A.values()): SK['no T-115 book on all three']+=1; continue
    ov=overround([R[n][1][A[n]] for n in R])
    w=sorted(R,key=lambda n:(-gap(R[n][1][A[n]],R[n][2][A[n]]),R[n][1][A[n]]))[0]
    sto,bp,lp,ltp,tv,ts=R[w]; i=A[w]; g0=gap(bp[i],lp[i])
    if g0<2: SK['widest gap is 1 tick, no inside']+=1; continue
    SK['signal markets']+=1
    live=np.where(sto>=300)[0]; e=int(live[-1]) if len(live) else i
    mv=float(np.log(((bp[i]+lp[i])/2)/((bp[e]+lp[e])/2)))
    for side,X in (('RLAY',up(bp[i])),('RBACK',dn(lp[i]))):
        if X<=1.01: SK['level at 1.01']+=1; continue
        for mode,cancel in (('LIVE',False),('CANCEL',True)):
            j=fill_at(side,sto,bp,lp,ltp,tv,i,X,cancel=cancel)
            d=dict(mid=mid_,ts=ts[i],ov=ov,gap0=g0,side=side,mode=mode,band=pband(X),X=X,filled=j is not None,mv=mv,pnl=np.nan,at_level=np.nan,why=None,wait=np.nan)
            if j is not None:
                k,why=exit_index(sto,bp,lp,j)
                if side=='RBACK': d.update(pnl=rback_pnl(X,lp[k]),at_level=back_pnl(X,lp[k]))
                else: d.update(pnl=rlay_pnl(X,bp[k]),at_level=lay_pnl(X,bp[k]))
                d.update(why=why,wait=(ts[j]-ts[i])/60)
            rows.append(d)
print("counts (not hidden):",dict(SK),flush=True)
D=pd.DataFrame(rows)
if D.empty: print("ERROR: no signals, so no verdict"); sys.exit(1)
med=D[D.ov>=103].ts.median() if (D.ov>=103).any() else D.ts.median(); D['late']=D.ts>=med
print(f"signals by market: OR>=103 {D[D.ov>=103].mid.nunique()}, OR<103 {D[D.ov<103].mid.nunique()} | days {pd.Timestamp(D.ts.min(),unit='s').date()}..{pd.Timestamp(D.ts.max(),unit='s').date()} | halves at {pd.Timestamp(med,unit='s',tz='UTC')}",flush=True)
def cell(side,mode,name,x):
    f=x[x.filled]; a=f[~f.late].pnl; b=f[f.late].pnl; u=x[~x.filled]
    return dict(side=side,mode=mode,cell=name,signals=len(x),fill=x.filled.mean(),n=len(f),per10=f.pnl.mean(),t=tstat(f.pnl),n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,
        per_sig=f.pnl.sum()/max(len(x),1),at_level=f.at_level.mean(),mv_f=f.mv.mean(),mv_u=u.mv.mean(),closed=(f.why=='closed').mean() if len(f) else np.nan,wait=f.wait.median())
out=[]
for (side,mode),x in D.groupby(['side','mode']):
    for lab,m in (('OR>=102',x.ov>=102),('OR>=103',x.ov>=103),('OR>=105',x.ov>=105),('CTRL OR<103',x.ov<103),('all',x.ov>0)):
        out.append(cell(side,mode,lab,x[m]))
    y=x[x.ov>=103]
    for b_,dd in y.groupby('band'): out.append(cell(side,mode,'OR>=103 px '+b_,dd))
    for g_,dd in y.groupby(pd.cut(y.gap0,[1,3,6,10,1000],labels=['gap2-3','gap4-6','gap7-10','gap11+']),observed=True): out.append(cell(side,mode,'OR>=103 '+str(g_),dd))
    z=x[x.ov<103]
    for g_,dd in z.groupby(pd.cut(z.gap0,[1,3,6,10,1000],labels=['gap2-3','gap4-6','gap7-10','gap11+']),observed=True): out.append(cell(side,mode,'CTRL '+str(g_),dd))
S=pd.DataFrame(out)
S['PASS']=(~S.cell.str.startswith('CTRL'))&(S.n>=300)&(S.n1>=150)&(S.n2>=150)&(S.t>=3.5)&(S.h1>0)&(S.h2>0)&(S.per10>=0.15)
print("\n== RESULTS per £10, by t\n",S.sort_values('t',ascending=False).drop(columns=['PASS']).round(3).to_string(index=False))
W=S[S.PASS==True]; print(f"\n== SURVIVORS: {len(W)} of {int((~S.cell.str.startswith('CTRL')).sum())} eligible lines"); print(W.drop(columns=['PASS']).round(3).to_string(index=False) if len(W) else "none")
PY
