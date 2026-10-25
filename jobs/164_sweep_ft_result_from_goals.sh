#!/bin/bash
# 164: SWEEP — FT SETTLEMENT BIAS. Winner was inferred from a final price <= 1.15; checked on 4,000 games: 18% of DRAWS never reach
# that (the draw price only collapses at the whistle, often after the last recorded minute) vs 5-8% of home/away wins. Those games were
# dropped from every FT cell, so "lay the draw to FT" looked +12% when it was mostly missing draws. Fix: result = goals counted from
# the draw jumps and their scorers (HOME goals vs AWAY goals); price only as a tiebreak when a scorer could not be identified. The job
# prints the agreement between goal-count results and price-decided results before trusting it. Sweep re-run; 165 then takes the
# surviving HEDGED cells (unaffected by this) to the live recorder data for an out-of-sample check with real back/lay prices.
cd /root/pe-factory/v4 && pkill -f sport_sweep.py; sleep 1
python3 - <<'PY'
p='sport_sweep.py'; s=open(p).read(); n=0
old='''    finals={s:P[s][MAXM] for s in SIDES}; finals={k:v for k,v in finals.items() if not np.isnan(v)}
    winner=None
    if finals:
        w=min(finals,key=finals.get)
        if finals[w]<=1.15: winner=w
    return P,LP,gl,scorers,winner'''
new='''    finals={s:P[s][MAXM] for s in SIDES}; finals={k:v for k,v in finals.items() if not np.isnan(v)}
    pwin=None
    if finals:
        w=min(finals,key=finals.get)
        if finals[w]<=1.15: pwin=w
    if any(sc is None for sc in scorers): winner=pwin                  # a goal we could not attribute: fall back to price
    else:
        hg=sum(1 for sc in scorers if sc=='HOME'); ag=sum(1 for sc in scorers if sc=='AWAY')
        winner='HOME' if hg>ag else ('AWAY' if ag>hg else 'DRAW')
    AGREE.append((winner,pwin))
    return P,LP,gl,scorers,winner'''
assert old in s; s=s.replace(old,new); n+=1
s=s.replace("SIDES=('HOME','DRAW','AWAY'); EXITS=","AGREE=[]; SIDES=('HOME','DRAW','AWAY'); EXITS=",1); n+=1
old2='''    R=pd.concat(parts,ignore_index=True)'''
new2='''    R=pd.concat(parts,ignore_index=True)
    A=pd.DataFrame(AGREE,columns=['goals','price']); both=A.dropna()
    print(f"result check: {len(A)} games | goal-count result available {A.goals.notna().mean():.1%} | price-decided {A.price.notna().mean():.1%} | agreement where both: {(both.goals==both.price).mean():.1%} (n {len(both)}) | goal-count draws {(A.goals=='DRAW').mean():.1%} vs price-decided draws {(A.price=='DRAW').sum()/max(1,A.price.notna().sum()):.1%}")'''
assert old2 in s; s=s.replace(old2,new2); n+=1
open(p,'w').write(s); print("patches:",n)
PY
python3 -m py_compile sport_sweep.py || exit 1
python3 - <<'PY'
import numpy as np, pandas as pd
src=open('/root/pe-factory/v4/sport_sweep.py').read().split("def main():")[0].replace("from bot_core import DB","DB=''"); ns={}; exec(src,ns)
rows=[]
for m in range(0,96):   # home scores 20', away equalises 60', game drawn; draw price only reaches 1.3 by 95 (would have been 'undecided')
    h=2.0 if m<20 else (1.4 if m<60 else 2.6); d=3.4 if m<20 else (5.0 if m<60 else max(1.3,2.4-0.03*(m-60))); a=3.5 if m<20 else (8.0 if m<60 else 4.5)
    for sel,p in (('HOME',h),('DRAW',d),('AWAY',a)): rows.append(dict(event_id='e',m=pd.Timestamp('2025-01-01'),minute=m,sel=sel,ltp=p))
g=pd.DataFrame(rows); P,LP,gl,sc,w=ns['parse_game'](g); print("goals",gl,"scorers",sc,"winner",w,"| price-decided:",ns['AGREE'][-1][1])
assert gl==[20,60] and sc==['HOME','AWAY'] and w=='DRAW' and ns['AGREE'][-1][1] is None; print("result-from-goals PASS")
PY
(nohup timeout 10000 python3 sport_sweep.py > sport_sweep.log 2>&1 &); echo "sweep restarted"
