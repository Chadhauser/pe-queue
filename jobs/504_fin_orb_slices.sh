#!/bin/bash
# 504: FINANCIAL — pull ORB-QQQ apart: slices by gap, first-bar range/ATR, vol regime, weekday, side; ONE filter chosen on the IS half,
# judged on OOS; filtered vs unfiltered through Topstep/Apex 50K Monte Carlo at $100/150/200. Explained to Peter 4 Nov 06:10. Tested offline.
cd /root/pe-fin
cat > orb_slices.py <<'PYFILE'
# 504: "Pull ORB apart" — which days does the QQQ ORB edge live on? Slices by overnight gap, first-5-min range vs 20-day ATR, 20-day
# realised vol tercile, day of week, month. Filter chosen on the IS half ONLY (first 50% of days), then judged on OOS. Then the
# filtered trade stream through Topstep/Apex 50K Monte Carlo at $100/$150/$200. Honest rule: one filter, chosen in-sample, reported out-of-sample.
import sys, math, numpy as np, pandas as pd, psycopg2
sys.path.insert(0,'/root/pe-fin'); from alpaca_load import load
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require'); T=pd.read_sql("SELECT date, side, r_pts, pts, r_mult, reason FROM orb_qqq_trades ORDER BY date",con); con.close()
T['date']=pd.to_datetime(T.date)
b=load('QQQ'); ny=b.index.tz_convert('America/New_York'); b=b.assign(d=ny.date, mi=ny.hour*60+ny.minute-570)
rth=b[(b.mi>=0)&(b.mi<390)]
D=rth.groupby('d').agg(o=('open','first'),h=('high','max'),l=('low','min'),c=('close','last'))
f5=rth[rth.mi<5].groupby('d').agg(h5=('high','max'),l5=('low','min'))
D=D.join(f5); D['prev']=D.c.shift(1); D['gap']=D.o/D.prev-1
tr=np.maximum(D.h-D.l,np.maximum((D.h-D.prev).abs(),(D.l-D.prev).abs())); D['atr20']=tr.rolling(20).mean().shift(1)
D['r5_atr']=(D.h5-D.l5)/D.atr20; D['vol20']=np.log(D.c).diff().rolling(20).std().shift(1)
D.index=pd.to_datetime(D.index); X=T.set_index('date').join(D[['gap','r5_atr','vol20']]); X['dow']=X.index.dayofweek; X['month']=X.index.month
n=len(X); half=X.index[n//2]; IS=X[X.index<half]; OOS=X[X.index>=half]
def st(s): s=s.dropna(); return (len(s), round(s.mean(),3), round(s.mean()/(s.std(ddof=1)/math.sqrt(len(s))),2) if len(s)>5 and s.std()>0 else None)
print(f"trades {n} | IS {len(IS)} OOS {len(OOS)} | ALL mean R {X.r_mult.mean():+.3f}")
X['gap_b']=pd.cut(X.gap.abs(),[-1,0.002,0.005,0.01,9],labels=['gap<0.2%','0.2-0.5%','0.5-1%','>1%'])
X['gapdir']=np.where(np.sign(X.gap)==X.side,'gap-with','gap-against')
X['r5_b']=pd.qcut(X.r5_atr,3,labels=['r5 small','r5 mid','r5 large'])
X['vol_b']=pd.qcut(X.vol20,3,labels=['vol low','vol mid','vol high'])
X['dow_b']=X.dow.map({0:'Mon',1:'Tue',2:'Wed',3:'Thu',4:'Fri'})
rows=[]
for col in ('gap_b','gapdir','r5_b','vol_b','dow_b','side'):
    for v,g in X.groupby(col):
        a,i,o=st(g.r_mult),st(g[g.index<half].r_mult),st(g[g.index>=half].r_mult)
        rows.append(dict(slice=f"{col}={v}",n=a[0],meanR=a[1],t=a[2],is_n=i[0],is_meanR=i[1],is_t=i[2],oos_n=o[0],oos_meanR=o[1],oos_t=o[2]))
S=pd.DataFrame(rows); print("\n=== slices (IS = first half of days, OOS = second) ==="); print(S.to_string(index=False))
# choose filter on IS only: the single slice with highest IS t and IS n>=150, must be a 'keep' rule; then test OOS
cand=S[(S.is_n>=max(40,int(0.15*len(IS))))].sort_values('is_t',ascending=False).iloc[0]
col,val=cand.slice.split('='); keep=X[X[col].astype(str)==val]
print(f"\nIS-chosen filter: {cand.slice} | IS meanR {cand.is_meanR} t {cand.is_t} -> OOS meanR {cand.oos_meanR} t {cand.oos_t} n {cand.oos_n}")
print("Unfiltered OOS for comparison:",st(OOS.r_mult))
# MC on filtered vs unfiltered, Apex & Topstep at $100/$150/$200
rng=np.random.default_rng(9)
def run(seq,risk,target,mll,trail_stop_at):
    bal=0.0; hi=0.0
    for x in seq:
        bal+=risk*x
        if bal>=target: return 'pass'
        hi=max(hi,bal)
        if bal<=min(hi,trail_stop_at)-mll: return 'bust'
    return 'neither'
print("\n=== Monte Carlo 3,000 x 250 trades: pass% / bust% ===")
for label,series in (('unfiltered',X.r_mult.values),(f'filtered[{cand.slice}]',keep.r_mult.values)):
    for firm,R in (('Topstep50K',dict(target=3000,mll=2000,trail_stop_at=2000)),('Apex50K',dict(target=3000,mll=2500,trail_stop_at=2500))):
        out=[]
        for risk in (100,150,200):
            c={'pass':0,'bust':0,'neither':0}
            for _ in range(3000): c[run(rng.choice(series,250,replace=True),risk,**R)]+=1
            out.append(f"${risk}: {100*c['pass']/3000:.0f}/{100*c['bust']/3000:.0f}")
        print(f"  {label:34s} {firm:11s} "+" | ".join(out))
print("\nREAD: a filter only counts if its OOS t holds up; if OOS collapses, the slice was noise and ORB stays unfiltered.")
PYFILE
python3 -m py_compile orb_slices.py || exit 1
timeout 1500 python3 orb_slices.py 2>&1 | grep -v Warning
