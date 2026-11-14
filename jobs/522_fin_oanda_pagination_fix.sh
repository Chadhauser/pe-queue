#!/bin/bash
# 522: BUG in 518's Oanda pull — pagination stopped after the second page (Oanda returns 4999 with includeFirst=false, my
# break condition was <5000), so every month holds only ~10k of ~30k bars and the FX tests ran on a third of the data
# (that is why F1 had 116 London days in 6 years). Fix, wipe, re-pull all 83 months x 6 instruments, reset F1-F10 to
# proposed so the Verifier regrades them on full data. Also fixes the MC's percentage display (showed 4732% for 47.32%).
cd /root/pe-fin || exit 1
python3 - <<'PY'
s=open('oanda_pull.py').read()
s=s.replace("if pd.Timestamp(t0)>=pd.Timestamp(f\"{m1}T00:00:00Z\") or len(c)<5000: break","if pd.Timestamp(t0)>=pd.Timestamp(f\"{m1}T00:00:00Z\") or len(c)<4000: break")
open('oanda_pull.py','w').write(s); print('patched' if 'len(c)<4000' in s else 'NOT PATCHED')
PY
grep -q "len(c)<4000" oanda_pull.py || exit 1
rm -rf /root/pe-data/oanda; echo "re-pulling (budget 2.5h)..."; python3 oanda_pull.py 2>&1 | tail -8
python3 - <<'PY'
import pandas as pd, glob
fs=sorted(glob.glob('/root/pe-data/oanda/EUR_USD/1m_2024-*.parquet')); n=[len(pd.read_parquet(f)) for f in fs]
print("EUR_USD 2024 bars per month:",n); assert min(n)>20000, "still truncated"
PY
cd /root/pe-fin/team && python3 - <<'PY'
import json; reg=json.load(open('hypotheses.json'))
for h in reg['hypotheses']:
    if h['id'] in [f'F{i}' for i in range(1,11)]: h['status']='proposed'
json.dump(reg,open('hypotheses.json','w'),indent=1); print('F1-F10 reset to proposed')
s=open('mc_lucid.py').read().replace("pass {100*res['pass_']/100:.0f}% bust {100*res['bust']/100:.0f}%","pass {res['pass_']/100:.0f}% bust {res['bust']/100:.0f}%"); open('mc_lucid.py','w').write(s)
PY
python3 -m py_compile mc_lucid.py && echo ok
