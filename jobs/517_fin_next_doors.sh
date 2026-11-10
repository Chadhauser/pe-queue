#!/bin/bash
# 517: next doors for the two clean near-misses (H2 BTC overnight -> QQQ t 1.51; M7 last-hour momentum t 1.64). One door each,
# pre-registered; if neither clears the bar they are dead (door 2 of 3 for H2, door 2 of 3 for M7).
cd /root/pe-fin/team || exit 1
cat > mech_next.py <<'PY'
import sys, json, math, numpy as np, pandas as pd
sys.path.insert(0,'/root/pe-fin'); sys.path.insert(0,'/root/pe-fin/team')
from mech2 import ret, move, bars, px_at, st, reg, H
import glob
@reg('H2b','BTC overnight (21:00 prev -> 09:25 ET) >=2% -> QQQ 09:30->11:00 SAME sign (H2 door 2: wider threshold, shorter hold).')
def H2b():
    fs=sorted(glob.glob('/root/pe-data/yf1m/BTC*.parquet'))+sorted(glob.glob('/root/pe-data/alpaca/BTCUSD/*.parquet'))
    b=pd.concat(pd.read_parquet(f) for f in fs).sort_index(); b=b[~b.index.duplicated()]
    ny=b.index.tz_convert('America/New_York'); b=b.assign(d=ny.date,mi=ny.hour*60+ny.minute)
    pre=b[b.mi==565].groupby('d').open.first(); prev=b[b.mi==1260].groupby('d').open.first()
    g={}
    for d in pre.index:
        p=[x for x in prev.index if x<d]
        if p and (d-p[-1]).days<=3: g[d]=pre[d]/prev[p[-1]]-1
    return ret('QQQ',0,90,lambda d: abs(g.get(d,0))>=0.02, lambda d: int(np.sign(g[d])))
@reg('M7b','Last-hour momentum, WIDER: QQQ 09:30->15:00 move >=1.5% -> WITH it 15:00->close (M7 door 2).')
def M7b():
    m=move('QQQ',0,330); return ret('QQQ',330,390,lambda d: abs(m.get(d,0))>=0.015, lambda d: int(np.sign(m[d])))
if __name__=='__main__':
    a=sys.argv[1] if len(sys.argv)>1 else 'list'
    if a=='list': [print(k,'—',f.__doc__) for k,f in H.items() if k in ('H2b','M7b')]; sys.exit(0)
    s=H[a](); R=st(s); rng=np.random.default_rng(17); C=st(s*rng.choice([-1,1],len(s)))
    print(a,H[a].__doc__); print('real',R); print('control',C)
    print("RESULT "+json.dumps(dict(name=f"{a} {H[a].__doc__[:70]}",n=R['n'],mean_bps=f"{R['mean']:+.2f} bps/trade",t=round(R['t'],2),is_mean=R['is_mean'],is_t=round(R['is_t'],2),oos_mean=R['oos_mean'],oos_t=round(R['oos_t'],2),control_t=round(C['t'],2))))
PY
python3 -m py_compile mech_next.py || exit 1
python3 - <<'PY'
import json; reg=json.load(open('hypotheses.json')); have={h['id'] for h in reg['hypotheses']}
for i,doc in (('H2b','H2 door 2'),('M7b','M7 door 2')):
    if i not in have: reg['hypotheses'].append({"id":i,"script":"/root/pe-fin/team/mech_next.py","args":[i],"status":"proposed","pre_registered_sign":doc+" (+ as stated)","next_door":"door 3: sibling instrument (SPY), then dead","timeout":1800})
json.dump(reg,open('hypotheses.json','w'),indent=1); print('queued H2b M7b')
PY
