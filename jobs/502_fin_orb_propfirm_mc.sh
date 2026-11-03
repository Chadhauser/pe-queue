#!/bin/bash
# 502: FINANCIAL — ORB-QQQ (501: 1,397 trades, mean R +0.166, t 2.43, both halves +, control -0.02) through Topstep/Apex 50K rules
# at risk $100-$500/trade. Signal fixed; only sizing varies. Also funded-stage $/month and 6-month survival. Explained to Peter 3 Nov 09:20.
cd /root/pe-fin && pip install -q sqlalchemy --break-system-packages 2>&1 | grep -v WARNING | tail -1
cat > orb_mc.py <<'PYFILE'
# 502: ORB-QQQ trade sequence (orb_qqq_trades, 1,397 trades Jul 2020-Oct 2026) through prop-firm rule sets at several risk sizes.
# The signal is fixed; only the sizing changes (sizing is not fitting). Rules (VERIFIED from firm pages Oct 2026 where noted, else UNVERIFIED):
#  Topstep 50K: target +$3,000; trailing max-loss $2,000 from end-of-day balance high (stops trailing at +$2,000... we trail until start+2000);
#               daily loss limit $1,000 (UNVERIFIED whether still enforced); consistency: best day <= 50% of total profit at pass.
#  Apex 50K:    target +$3,000; trailing threshold $2,500 (trails intraday on unrealised, here EOD approx); no DLL; 30%-of-profit consistency for payout only.
# Output: pass/bust % per risk size, median days to pass, and funded-stage expectancy per month at 90% split with the same MLL.
import sys, math, numpy as np, pandas as pd, psycopg2
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require'); T=pd.read_sql("SELECT date, r_mult FROM orb_qqq_trades ORDER BY date",con); con.close()
r=T.r_mult.values.astype(float); n=len(r); print(f"trades {n} | mean R {r.mean():+.3f} | OOS half mean R {r[n//2:].mean():+.3f}")
rng=np.random.default_rng(5)
def run(seq,risk,target,mll,dll,trail_stop_at,consist):
    bal=0.0; hi=0.0; days=0; best=-1e9; worst_day=0
    for x in seq:
        pnl=risk*x; days+=1
        if dll and pnl<=-dll: pnl=-dll
        bal+=pnl; best=max(best,pnl)
        if bal>=target and (not consist or best<=consist*bal): return 'pass',days
        hi=max(hi,bal); floor=min(hi,trail_stop_at)-mll
        if bal<=floor: return 'bust',days
    return 'neither',days
FIRMS={'Topstep50K':dict(target=3000,mll=2000,dll=1000,trail_stop_at=2000,consist=0.5),
       'Topstep50K_noDLL':dict(target=3000,mll=2000,dll=None,trail_stop_at=2000,consist=0.5),
       'Apex50K':dict(target=3000,mll=2500,dll=None,trail_stop_at=2500,consist=None)}
rows=[]
for firm,R in FIRMS.items():
    for risk in (100,150,200,250,300,400,500):
        res={'pass':0,'bust':0,'neither':0}; dpass=[]
        for _ in range(4000):
            seq=rng.choice(r,size=250,replace=True); o,d=run(seq,risk,**R); res[o]+=1
            if o=='pass': dpass.append(d)
        rows.append(dict(firm=firm,risk=risk,pass_pct=round(100*res['pass']/4000,1),bust_pct=round(100*res['bust']/4000,1),median_days_to_pass=int(np.median(dpass)) if dpass else None))
P=pd.DataFrame(rows); print("\n=== evaluation pass/bust by risk per trade (4,000 shuffles of 250 trades each) ==="); print(P.to_string(index=False))
# funded stage: same MLL, 90% split, monthly expectancy = 21 trades; P(survive 6 months) by bootstrap
print("\n=== funded 50K, 90% split: expected $/month and 6-month survival (MLL trailing as above) ===")
for risk in (100,200,300):
    surv=0; pm=[]
    for _ in range(3000):
        seq=rng.choice(r,size=126,replace=True); o,d=run(seq,risk,target=1e12,mll=2000,dll=None,trail_stop_at=2000,consist=None)
        if o!='bust': surv+=1; pm.append(risk*seq.sum()*0.9/6)
    print(f"risk ${risk}: survive 6m {100*surv/3000:.0f}% | mean $/month if alive {np.mean(pm):,.0f} | median {np.median(pm):,.0f}")
print("\nREAD: pass% must beat bust% clearly; a 1-in-3 pass at $500 risk is the trailing-MLL (4R) biting, not the signal. Smaller risk = slower pass but higher odds.")
PYFILE
python3 -m py_compile orb_mc.py || exit 1
timeout 1500 python3 orb_mc.py 2>&1 | grep -v Warning
