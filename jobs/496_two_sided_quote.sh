#!/bin/bash
set -o pipefail
# 496 (Finder 2026-11-04, queue item 47): QUOTE BOTH SIDES INSIDE THE GAP, no crossing unless stuck. stream_ticks football MO_PRE, pre-off, OPEN, whole rolling table (range printed). PILOT.
# ANCHOR as jobs 485/494: last tick at or before T-115 min, no older than 300 s, on all three runners. RUNNER = widest gap in ladder ticks; quoted only if gap >= 4, counted otherwise.
# QUOTES: rest a lay at XL = back_px +1 tick and a back at XB = lay_px -1 tick. One round per market.
# FILL (strict, as 492/494): a fresh print (runner's traded volume up on the previous tick; a stale ltp is not a print) strictly THROUGH the level: below XL fills the lay, above XB fills the back. Nothing at the level counts, so queue position is never assumed. Live to T-5.
# AFTER THE FIRST FILL the same-side order is gone; the other order, resized to green the position, stays to T-5. If it fills: GREEN. If not: CROSS the opposite touch on the last tick at or before T-5 (else the fill tick's own book). Pre-off positions do not settle, nothing to settle at result.
# COST: per10 = one tick adverse on every entry and exit (house rule, and what PASS reads). So a green earns gap-4 ticks: gap 4 is exactly £0. at_level = both resting legs at exactly their level, a cross still one tick adverse; diagnostic only. £10 risk: back stake £10; lay liability £10. 2% commission on net profit per market.
# One trade per market, one runner per market, so t is not inflated by repeat entries. Halves: median signal time of all quoted markets. per_quote = total P&L / markets quoted (unfilled = £0). The first-side split is reported for reading.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,warnings,psycopg2,pandas as pd,numpy as np
from collections import Counter
warnings.filterwarnings('ignore')
pd.set_option('display.width',260); pd.set_option('display.max_rows',120); pd.set_option('display.max_columns',30)
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
def green_back_first(eb,el): return comm(10*(eb/el-1))                 # back stake £10 at eb, lay out at el
def green_lay_first(el,eb): return comm(10/(el-1)*(1-el/eb))           # lay liability £10 at el, back out at eb
def cross_back(eb,lp): return comm(10*(eb/up(lp)-1))                   # holding a back: lay one tick above the lay touch
def cross_lay(el,bp): return comm(10/(el-1)*(1-el/max(1.01,dn(bp))))   # holding a lay: back one tick below the back touch
def anchor(sto,x,maxage=300):
    idx=np.where(sto>=x)[0]
    if len(idx)==0: return None
    i=idx[-1]
    return int(i) if sto[i]-x<=maxage else None
def overround(backs): return 100*sum(1/b for b in backs)
def quote(sto,bp,lp,ltp,tv,i,tlast=300):
    """None if neither order fills, else first side, fill index, outcome (GREEN/CROSS), exit index, per10, at_level."""
    XL,XB=up(bp[i]),dn(lp[i])
    first=None; j1=None; last=i
    for j in range(i+1,len(sto)):
        if sto[j]<tlast: break
        last=j
        if not tv[j]>tv[j-1] or not np.isfinite(ltp[j]): continue
        if first is None:
            if ltp[j]<XL-1e-9: first,j1='LAY',j
            elif ltp[j]>XB+1e-9: first,j1='BACK',j
        elif first=='LAY' and ltp[j]>XB+1e-9:
            return dict(first='LAY',j1=j1,out='GREEN',k=j,per10=green_lay_first(up(XL),dn(XB)),at_level=green_lay_first(XL,XB))
        elif first=='BACK' and ltp[j]<XL-1e-9:
            return dict(first='BACK',j1=j1,out='GREEN',k=j,per10=green_back_first(dn(XB),up(XL)),at_level=green_back_first(XB,XL))
    if first is None: return None
    k=max(last,j1)
    if first=='LAY': return dict(first='LAY',j1=j1,out='CROSS',k=k,per10=cross_lay(up(XL),bp[k]),at_level=cross_lay(XL,bp[k]))
    return dict(first='BACK',j1=j1,out='CROSS',k=k,per10=cross_back(dn(XB),lp[k]),at_level=cross_back(XB,lp[k]))
def pband(p): return '<2' if p<2 else '2-3' if p<3 else '3-5' if p<5 else '5-10' if p<10 else '10+'
def tstat(v):
    v=np.asarray(v,dtype=float)
    if len(v)<2: return 0.0
    s=v.std(ddof=1); return float(v.mean()/(s/len(v)**0.5)) if s>0 else 0.0
# known answers, worked by hand
assert gap(2.0,2.08)==4 and gap(2.94,3.05)==4 and up(2.0)==2.02 and dn(2.08)==2.06 and up(2.98)==3.0
assert green_back_first(2.04,2.04)==0 and green_lay_first(2.04,2.04)==0        # gap 4: levels 2.02/2.06, adverse both to 2.04, exactly £0
assert abs(green_lay_first(2.04,2.08)-0.181210)<1e-5                           # gap 6: 10/1.04=9.61538 x (1-2.04/2.08)=0.184911, x0.98
assert abs(green_back_first(2.08,2.04)-0.192157)<1e-5                          # gap 6: 10 x (2.08/2.04-1)=0.196078, x0.98
assert abs(cross_back(2.04,2.5)-(-1.904762))<1e-5                              # stuck long, drifted: lay at 2.52, a loss, no commission
assert abs(cross_lay(2.04,1.8)-(-1.342926))<1e-5                               # stuck short, shortened: back at 1.79, a loss, no commission
assert abs(cross_back(2.04,1.8)-1.245304)<1e-5                                 # stuck long, shortened: lay at 1.81, 1.270718 x0.98
_s=np.array([6900.,6000.,5000.,4000.,200.]); _b=np.full(5,2.0); _l=np.full(5,2.12); _v=np.array([10.,20,30,40,50])   # gap 6, XL 2.02, XB 2.10
_r=quote(_s,_b,_l,np.array([2.0,2.01,2.11,2.06,2.06]),_v,0); assert _r['first']=='LAY' and _r['out']=='GREEN' and _r['j1']==1 and _r['k']==2 and abs(_r['per10']-0.181210)<1e-5
_r=quote(_s,_b,_l,np.array([2.0,2.11,2.01,2.06,2.06]),_v,0); assert _r['first']=='BACK' and _r['out']=='GREEN' and abs(_r['per10']-0.192157)<1e-5 and abs(_r['at_level']-0.98*10*(2.10/2.02-1))<1e-5
assert quote(_s,_b,_l,np.array([2.0,2.02,2.10,2.06,2.06]),_v,0) is None         # prints AT both levels: no fill
assert quote(_s,_b,_l,np.array([2.0,2.01,2.11,2.11,2.11]),np.full(5,10.),0) is None   # through both with flat volume: stale, no fill
assert quote(_s,_b,_l,np.array([2.0,2.06,2.06,2.06,1.5]),_v,0) is None          # through only past T-5: order already cancelled
_r=quote(_s,_b,_l,np.array([2.0,2.01,2.06,2.06,2.11]),_v,0)                     # second through only past T-5: not green, cross last live tick (index 3)
assert _r['out']=='CROSS' and _r['k']==3 and abs(_r['per10']-cross_lay(2.04,2.0))<1e-9 and _r['per10']<0
_r=quote(_s,_b,_l,np.array([2.0,2.06,2.06,2.01,2.06]),_v,0); assert _r['j1']==3 and _r['out']=='CROSS' and _r['k']==3   # filled on the last live tick: the fill tick's own book
assert quote(_s,_b,_l,np.array([2.0,np.nan,2.06,2.06,2.06]),_v,0) is None       # null ltp is not a print
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
      FROM stream_ticks WHERE ts_recv>=%s AND ts_recv<%s AND sport='football' AND mkt='MO_PRE' AND inplay=false AND status='OPEN' AND secs_to_off>=300 AND secs_to_off<=7200""",(a,a+pd.Timedelta(hours=6)))
    d=pd.DataFrame(cur.fetchall(),columns=['mid','sel','ts','sto','bp','lp','ltp','tv']); parts.append(d)
    print(f"  chunk {a}: {len(d)} ticks ({int(time.time()-t0)}s)",flush=True)
con.close()
T=pd.concat(parts,ignore_index=True); n_all=len(T)
T=T.dropna(subset=['bp','lp','sto'])
for c in ('bp','lp','ltp'): T[c]=T[c].astype(float).round(2)
T=T[(T.bp>1)&(T.lp>T.bp)&(T.lp<1000)].sort_values(['mid','sel','ts'],kind='stable')
print(f"ticks {n_all}, usable touch {len(T)}, markets {T.mid.nunique()}, ltp null {T.ltp.isna().mean():.1%}, tv null or zero {((T.tv.isna())|(T.tv<=0)).mean():.1%}",flush=True)
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
    if g0<4: SK['widest gap under 4 ticks']+=1; continue
    SK['quoted markets']+=1
    q=quote(sto,bp,lp,ltp,tv,i)
    d=dict(mid=mid_,ts=ts[i],ov=ov,gap0=g0,band=pband((bp[i]+lp[i])/2),filled=q is not None,first=None,out='NONE',per10=0.0,at_level=0.0,mv=np.nan,age=np.nan,wait1=np.nan,wait2=np.nan)
    if q:
        j,k=q['j1'],q['k']; mv=float(np.log(((bp[j]+lp[j])/2)/((bp[k]+lp[k])/2)))
        d.update(first=q['first'],out=q['out'],per10=q['per10'],at_level=q['at_level'],mv=(mv if q['first']=='BACK' else -mv),wait1=(ts[j]-ts[i])/60)
        if q['out']=='GREEN': d['wait2']=(ts[k]-ts[j])/60
        else: d['age']=sto[k]-300
    rows.append(d)
print("counts (not hidden):",dict(SK),flush=True)
D=pd.DataFrame(rows)
if D.empty: print("ERROR: no quoted markets, so no verdict"); sys.exit(1)
med=D.ts.median(); D['late']=D.ts>=med
print(f"quoted markets {len(D)} | days {pd.Timestamp(D.ts.min(),unit='s').date()}..{pd.Timestamp(D.ts.max(),unit='s').date()} | halves at {pd.Timestamp(med,unit='s',tz='UTC')}",flush=True)
print(f"outcomes: none {(D.out=='NONE').sum()}, green {(D.out=='GREEN').sum()}, cross {(D.out=='CROSS').sum()} | first LAY {(D['first']=='LAY').sum()}, first BACK {(D['first']=='BACK').sum()}",flush=True)
print(f"median minutes: signal to first fill {D.wait1.median():.1f}, first to second {D.wait2.median():.1f}; cross exit book older than T-5 by median {D.age.median():.0f} s, p90 {D.age.quantile(.9):.0f} s",flush=True)
print(f"mv > 0 = the market moved for the position, first fill to exit: green {D[D.out=='GREEN'].mv.mean():.4f}, cross {D[D.out=='CROSS'].mv.mean():.4f}",flush=True)
def cell(name,x):
    f=x[x.filled]; a=f[~f.late].per10; b=f[f.late].per10; g=f[f.out=='GREEN']; c=f[f.out=='CROSS']
    return dict(cell=name,quoted=len(x),fill=x.filled.mean(),both=(x.out=='GREEN').mean(),both_of_filled=(f.out=='GREEN').mean() if len(f) else np.nan,n=len(f),per10=f.per10.mean(),t=tstat(f.per10),n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,
        per_quote=f.per10.sum()/max(len(x),1),t_quote=tstat(x.per10),at_level=f.at_level.mean(),green=g.per10.mean(),n_cross=len(c),cross=c.per10.mean())
out=[cell('all gap>=4',D)]
for lab,m in (('OR>=102',D.ov>=102),('OR>=103',D.ov>=103),('OR>=105',D.ov>=105),('OR<103',D.ov<103)): out.append(cell(lab,D[m]))
GB=[3,4,6,10,1000]; GL=['gap4','gap5-6','gap7-10','gap11+']
for g_,dd in D.groupby(pd.cut(D.gap0,GB,labels=GL),observed=True): out.append(cell(str(g_),dd))
for lab,m in (('OR>=103',D.ov>=103),('OR<103',D.ov<103)):
    for g_,dd in D[m].groupby(pd.cut(D[m].gap0,GB,labels=GL),observed=True): out.append(cell(lab+' '+str(g_),dd))
for b_,dd in D.groupby('band'): out.append(cell('px '+b_,dd))
for f_,dd in D[D.filled].groupby('first'): out.append(cell('first '+f_,dd))
S=pd.DataFrame(out)
S['PASS']=(S.n>=300)&(S.n1>=150)&(S.n2>=150)&(S.t>=3.5)&(S.h1>0)&(S.h2>0)&(S.per10>=0.15)
print("\n== RESULTS per £10, by t (n = markets with a fill; per_quote counts unfilled as £0)\n",S.sort_values('t',ascending=False).drop(columns=['PASS']).round(3).to_string(index=False))
W=S[S.PASS==True]; print(f"\n== SURVIVORS: {len(W)} of {len(S)} lines"); print(W.drop(columns=['PASS']).round(3).to_string(index=False) if len(W) else "none")
PY
