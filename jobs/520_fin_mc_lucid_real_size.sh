#!/bin/bash
# 520: honest re-size. On MNQ the smallest trade is 1 contract, and a typical ORB-QQQ day has a 5-min range of ~3.5 QQQ points
# = ~130 NQ points = ~$260 at risk per contract. So "$100 risk" is not available; real risk is 1 contract = $150-350/day.
# Re-run the prop-firm Monte Carlo at the ACTUAL 1-contract risk under Lucid $50K rules (EOD trailing MLL $2,000 that locks at
# the start balance, target $3,000, no daily limit, no minimum days). Prints RESULT lines; the header quotes this, not the old $100 MC.
cd /root/pe-fin/team || exit 1
cat > mc_lucid.py <<'PY'
import sys, json, math, datetime as dt, numpy as np, pandas as pd
sys.path.insert(0,'/root/pe-fin'); sys.path.insert(0,'/root/pe-fin/team')
from mech2 import bars
RATIO=float(sys.argv[1]) if len(sys.argv)>1 else 37.6   # NQ points per QQQ point (both track NDX; ~25,000/665 in Nov 2026)
b=bars('QQQ'); COST=0.03; rows=[]
for d,sess in b.groupby('d'):
    if len(sess)<300: continue
    fb=sess[sess.mi<5]; rest=sess[sess.mi>=5]
    if len(fb)<3 or not len(rest): continue
    o,c,hi,lo=fb.open.iloc[0],fb.close.iloc[-1],fb.high.max(),fb.low.min(); rng=hi-lo
    if rng<=0 or abs(c-o)<0.05*rng: continue
    side=1 if c>o else -1; entry=rest.open.iloc[0]; stop=lo if side>0 else hi; R=abs(entry-stop)
    if R<=0 or (side>0 and stop>=entry) or (side<0 and stop<=entry): continue
    target=entry+side*10*R; ex=rest.close.iloc[-1]
    for r in rest.itertuples():
        if side>0 and (r.low<=stop or r.high>=target): ex=stop if r.low<=stop else target; break
        if side<0 and (r.high>=stop or r.low<=target): ex=stop if r.high>=stop else target; break
    rows.append(dict(date=pd.Timestamp(d),R_q=R,r_mult=(side*(ex-entry)-COST)/R))
T=pd.DataFrame(rows).set_index('date'); T['R_pts']=(T.R_q*RATIO/0.25).round()*0.25; T['risk_1c']=T.R_pts*2.0   # 1 MNQ contract, $2/pt
T['pnl_1c']=T.r_mult*T.risk_1c-2*0.62   # $0.62 commission+fees per side per MNQ (Tradovate micro)
print(f"days {len(T)} | median 1-contract risk ${T.risk_1c.median():.0f} | mean ${T.risk_1c.mean():.0f} | 90th pct ${T.risk_1c.quantile(.9):.0f} | mean pnl/day ${T.pnl_1c.mean():+.2f}")
def mc(pnl,target=3000,mll=2000,n=10000,seed=1):
    rng=np.random.default_rng(seed); res=dict(pass_=0,bust=0,open_=0); days=[]
    for _ in range(n):
        seq=rng.choice(pnl,size=400,replace=True); bal=0.0; hi=0.0; floor=-mll; out='open_'
        for i,x in enumerate(seq):
            bal+=x
            if bal>=target: out='pass_'; days.append(i+1); break
            hi=max(hi,bal); floor=min(max(floor,hi-mll),0.0)      # trails up to the start balance then locks
            if bal<=floor: out='bust'; break
        res[out]+=1
    return res, (int(np.median(days)) if days else None)
h=len(T)//2
for label,sub in (('ALL',T),('OOS second half',T.iloc[h:]),('last 2 years',T[T.index>=T.index[-1]-pd.Timedelta(days=730)])):
    res,med=mc(sub.pnl_1c.values); print(label,res,'median trading days to pass',med)
    print("RESULT "+json.dumps(dict(name=f"MC Lucid 50K, 1 MNQ contract ({label}, {len(sub)} days): pass {100*res['pass_']/100:.0f}% bust {100*res['bust']/100:.0f}% median {med}d",n=len(sub),mean_bps=f"${sub.pnl_1c.mean():+.0f}/day",t=0,is_mean=0,is_t=0,oos_mean=0,oos_t=0,control_t=0)))
# funded: monthly expectation at 1 contract, after 90/10 split
m=T.pnl_1c.mean()*21*0.9; print(f"funded expectation at 1 contract: ${m:+.0f}/month after split = £{m*0.77:+.0f}")
PY
python3 -m py_compile mc_lucid.py || exit 1
python3 -I mc_lucid.py 37.6 2>&1 | tail -12
