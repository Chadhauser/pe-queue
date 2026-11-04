#!/bin/bash
set -o pipefail
# 499_follow_first_print (Finder 2026-11-04, queue item 49): FOLLOW THE FIRST PRINT THROUGH A WIDE PRE-MATCH BOOK. stream_ticks football MO_PRE, pre-off, OPEN, whole rolling table. PILOT. The number 499 is reused with a new slug: 450-499 are all taken.
# ANCHOR as jobs 485/494/496: last tick at or before T-115, no older than 300 s, all three runners; widest-gap runner; gap >= 4 is the test, gap 1-3 the control.
# SIGNAL: levels XL = back_px +1 tick, XB = lay_px -1 tick. First fresh print (traded volume up on the previous tick) strictly through: below XL = FOLLOW is back, above XB = FOLLOW is lay. Nothing after T-5.
# ENTRY: cross at the touch of the NEXT tick on that runner, as a trader cannot act on the print's own tick; none before T-5 = no trade, counted. Back at back_px, lay at lay_px, one tick adverse. same_tick = at the print's own book, a sensitivity, not what PASS reads.
# EXIT: opposite touch on the last tick at or before T-5, one tick adverse. Pre-off positions do not settle. £10 risk: back stake £10; lay liability £10. 2% on net profit. exact = no adverse ticks, diagnostic. FADE = the other side at the same tick, costs the same.
# One trade per market. Halves: median signal time. mv = log move of the mid from entry to exit, positive = for the position, no green exit, the item's unconditional move.
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
def anchor(sto,x,maxage=300):
    idx=np.where(sto>=x)[0]
    if len(idx)==0: return None
    i=idx[-1]
    return int(i) if sto[i]-x<=maxage else None
def overround(backs): return 100*sum(1/b for b in backs)
def signal(sto,bp,lp,ltp,tv,i,tlast=300):
    """(j,'BACK'|'LAY') for the first fresh print strictly through a level, else None."""
    XL,XB=up(bp[i]),dn(lp[i])
    for j in range(i+1,len(sto)):
        if sto[j]<tlast: break
        if not tv[j]>tv[j-1] or not np.isfinite(ltp[j]): continue
        if ltp[j]<XL-1e-9: return j,'BACK'
        if ltp[j]>XB+1e-9: return j,'LAY'
    return None
def rt(side,e_bp,e_lp,x_bp,x_lp,adverse=True):
    """Round trip on £10: BACK at e_bp, out at x_lp; LAY at e_lp (liability £10), out at x_bp."""
    if side=='BACK':
        a=dn(e_bp) if adverse else e_bp; q=up(x_lp) if adverse else x_lp
        return comm(10*(a/q-1)) if a>1.01 else None
    a=up(e_lp) if adverse else e_lp; q=max(1.01,dn(x_bp)) if adverse else x_bp
    return comm(10/(a-1)*(1-a/q))
def last_live(sto,tlast=300):
    idx=np.where(sto>=tlast)[0]
    return int(idx[-1]) if len(idx) else None
def pband(p): return '<2' if p<2 else '2-3' if p<3 else '3-5' if p<5 else '5-10' if p<10 else '10+'
def tstat(v):
    v=np.asarray(v,dtype=float)
    if len(v)<2: return 0.0
    s=v.std(ddof=1); return float(v.mean()/(s/len(v)**0.5)) if s>0 else 0.0
# known answers, worked by hand
assert gap(2.0,2.08)==4 and up(2.0)==2.02 and dn(2.12)==2.1 and dn(2.0)==1.99 and up(2.12)==2.14
_s=np.array([6900.,6000.,5000.,4000.,200.]); _b=np.full(5,2.0); _l=np.full(5,2.12); _v=np.array([10.,20,30,40,50])   # XL 2.02, XB 2.10
assert signal(_s,_b,_l,np.array([2.0,2.01,2.06,2.06,2.06]),_v,0)==(1,'BACK') and signal(_s,_b,_l,np.array([2.0,2.11,2.06,2.06,2.06]),_v,0)==(1,'LAY')
assert signal(_s,_b,_l,np.array([2.0,2.02,2.10,2.06,2.06]),_v,0) is None                  # prints AT both levels
assert signal(_s,_b,_l,np.array([2.0,2.01,2.11,2.11,2.11]),np.full(5,10.),0) is None      # flat volume is a stale ltp
assert signal(_s,_b,_l,np.array([2.0,np.nan,2.06,2.06,2.06]),_v,0) is None                # null ltp is not a print
assert signal(_s,_b,_l,np.array([2.0,2.06,2.06,2.06,1.5]),_v,0) is None                   # through only past T-5
assert abs(rt('BACK',2.0,2.12,2.0,2.12)-(-0.7009346))<1e-6                                # 10*(1.99/2.14-1)
assert abs(rt('LAY',2.0,2.12,2.0,2.12)-(-0.661201))<1e-5                                  # 10/1.14*(1-2.14/1.99): 8.771930 x 0.0753769
assert abs(rt('BACK',2.0,2.12,1.88,1.9)-0.4104712)<1e-6                                   # 10*(1.99/1.91-1)=.418848, *.98
assert abs(rt('LAY',2.0,2.12,2.5,2.52)-(10/1.14*(1-2.14/2.48))*0.98)<1e-9                 # price drifted, lay wins
assert rt('BACK',1.02,1.03,1.5,1.52) is None and rt('BACK',2.0,2.12,2.0,2.0,adverse=False)==0
assert last_live(_s)==3 and last_live(np.array([200.])) is None and anchor(np.array([7100.,6950.,6800.]),6900)==1 and anchor(np.array([7300.]),6900) is None
assert pband(1.99)=='<2' and pband(10.0)=='10+' and abs(tstat([1,3])-2.0)<1e-9 and abs(overround([2,4,4])-100)<1e-9
print("known-answer checks: OK",flush=True)
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
T=pd.concat(parts,ignore_index=True); n_all=len(T); T=T.dropna(subset=['bp','lp','sto'])
for c in ('bp','lp','ltp'): T[c]=T[c].astype(float).round(2)
T=T[(T.bp>1)&(T.lp>T.bp)&(T.lp<1000)].sort_values(['mid','sel','ts'],kind='stable')
print(f"ticks {n_all}, usable touch {len(T)}, markets {T.mid.nunique()}",flush=True)
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
    sto,bp,lp,ltp,tv,ts=R[w]; i=A[w]; g0=gap(bp[i],lp[i]); grp='TEST' if g0>=4 else 'CTRL'
    s=signal(sto,bp,lp,ltp,tv,i)
    if s is None: SK[grp+' no signal']+=1; continue
    j,side=s; k=last_live(sto); e=j+1
    if e>k: SK[grp+' signal on the last tick, no entry']+=1; continue
    other='LAY' if side=='BACK' else 'BACK'
    fo=rt(side,bp[e],lp[e],bp[k],lp[k]); fa=rt(other,bp[e],lp[e],bp[k],lp[k])
    if fo is None or fa is None: SK[grp+' price too short to back']+=1; continue
    mv=float(np.log(((bp[e]+lp[e])/2)/((bp[k]+lp[k])/2))); mv=mv if side=='BACK' else -mv
    rows.append(dict(mid=mid_,grp=grp,ts=ts[j],ov=ov,gap0=g0,band=pband((bp[e]+lp[e])/2),side=side,follow=fo,fade=fa,exact=rt(side,bp[e],lp[e],bp[k],lp[k],adverse=False),exact_fade=rt(other,bp[e],lp[e],bp[k],lp[k],adverse=False),same=rt(side,bp[j],lp[j],bp[k],lp[k]),mv=mv,gap_e=gap(bp[e],lp[e]),gap_x=gap(bp[k],lp[k]),hold=(ts[k]-ts[e])/60,stale=sto[k]-300,wait=(ts[j]-ts[i])/60))
print("counts (not hidden):",dict(SK),flush=True)
D=pd.DataFrame(rows)
if D.empty: print("ERROR: no trades, so no verdict"); sys.exit(1)
med=D[D.grp=='TEST'].ts.median(); D['late']=D.ts>=med
print(f"trades {D.grp.value_counts().to_dict()} | days {pd.Timestamp(D.ts.min(),unit='s').date()}..{pd.Timestamp(D.ts.max(),unit='s').date()} | halves at {pd.Timestamp(med,unit='s',tz='UTC')}")
print(D.groupby('grp')[['wait','hold','gap_e','gap_x','stale']].median().round(1).to_string()); print("mean mv by group and side:\n",D.groupby(['grp','side']).mv.agg(['size','mean']).round(4).to_string(),flush=True)
def cell(name,x,c='follow'):
    a=x[~x.late][c].dropna(); b=x[x.late][c].dropna(); v=x[c].dropna()
    return dict(cell=name,line=c,n=len(v),per10=v.mean(),t=tstat(v),n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,mv=x.mv.mean(),exact=x.exact.mean(),exact_fade=x.exact_fade.mean(),same=x.same.mean(),worst=v.min() if len(v) else np.nan,best=v.max() if len(v) else np.nan)
out=[]; X=D[D.grp=='TEST']; GB=[3,4,6,10,1000]; GL=['gap4','gap5-6','gap7-10','gap11+']
for c in ('follow','fade'):
    out.append(cell('TEST all',X,c)); out.append(cell('CTRL gap<4',D[D.grp=='CTRL'],c))
    for lab,m in (('OR>=103',X.ov>=103),('OR<103',X.ov<103),('side BACK',X.side=='BACK'),('side LAY',X.side=='LAY')): out.append(cell(lab,X[m],c))
    for g_,dd in X.groupby(pd.cut(X.gap0,GB,labels=GL),observed=True): out.append(cell(str(g_),dd,c))
    for b_,dd in X.groupby('band'): out.append(cell('px '+b_,dd,c))
S=pd.DataFrame(out); S['PASS']=(S.n>=300)&(S.n1>=150)&(S.n2>=150)&(S.t>=3.5)&(S.h1>0)&(S.h2>0)&(S.per10>=0.15)
print("\n== RESULTS per £10, by t\n",S.sort_values('t',ascending=False).drop(columns=['PASS']).round(3).to_string(index=False))
W=S[S.PASS==True]; print(f"\n== SURVIVORS: {len(W)} of {len(S)} lines"); print(W.drop(columns=['PASS']).round(3).to_string(index=False) if len(W) else "none"); print(f"total {time.time()-t0:.0f}s")
PY
