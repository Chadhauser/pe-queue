#!/bin/bash
# 265: Dukascopy repair. (a) ~390 NQ day files are zero-row "no data" markers written by 240's first slices before the 262 fix
#     (a throttled day looked like a holiday) -> delete every zero-row day file so the downloader refetches them.
#     (b) throttling: 8 parallel requests -> 4, plus 2s backoff after any ERR hour. (c) report true row-bearing day counts.
cd /root/pe-fin || exit 1
python3 - <<'PY'
import os, pandas as pd
base='/root/pe-data/duka'; tot={}
for sym in os.listdir(base):
    d=f"{base}/{sym}"; removed=0; kept=0
    for f in sorted(os.listdir(d)):
        if not f.startswith('day_'): continue
        try: n=len(pd.read_parquet(f"{d}/{f}"))
        except Exception: n=-1
        if n<=0: os.remove(f"{d}/{f}"); removed+=1
        else: kept+=1
    tot[sym]=(kept,removed); print(f"{sym}: days with rows {kept} | zero-row markers deleted {removed}")
PY
python3 - <<'PY'
p='/root/pe-fin/duka_1m.py'; s=open(p).read()
s=s.replace("with ThreadPoolExecutor(8) as ex:","with ThreadPoolExecutor(4) as ex:")
old="        frames=[r for r in res if isinstance(r,pd.DataFrame)]; errs+=sum(1 for r in res if isinstance(r,str))"
new="        frames=[r for r in res if isinstance(r,pd.DataFrame)]; e=sum(1 for r in res if isinstance(r,str)); errs+=e\n        if e: time.sleep(2+min(e,10))   # backoff when throttled"
assert old in s; s=s.replace(old,new)
s=s.replace("nonempty=[f for f in files if os.path.getsize(f\"{BASE}/{sym}/{f}\")>2000]","nonempty=[f for f in files if len(pd.read_parquet(f\"{BASE}/{sym}/{f}\"))>0]")
open(p,'w').write(s); print('downloader: 4 workers, backoff on ERR, true row count')
PY
python3 -m py_compile /root/pe-fin/duka_1m.py && echo "265 done — 240 keeps resuming and will refill the deleted days (NQ first)"
