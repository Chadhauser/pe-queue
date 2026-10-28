#!/bin/bash
# 280: 270 reported NQ "days on disk 628 (with data 73)" — 555 zero-row holiday markers left by the retired 240 made the downloader
# skip NQ entirely. Purge every zero-row day file (true holidays simply come back as 404 markers), and log the exception TYPE on
# non-HTTP failures (status counts were empty, so refusals are connection-level: timeouts/resets).
set -e; cd /root/pe-fin
python3 - <<'PY'
import os, pandas as pd
base='/root/pe-data/duka'
for sym in sorted(os.listdir(base)):
    d=f"{base}/{sym}"; z=0; k=0
    for f in sorted(os.listdir(d)):
        if not f.startswith('day_'): continue
        n=len(pd.read_parquet(f"{d}/{f}"))
        if n==0: os.remove(f"{d}/{f}"); z+=1
        else: k+=1
    print(f"{sym}: kept {k} complete days | purged {z} zero-row markers")
PY
python3 - <<'PY'
p='/root/pe-fin/duka_1m.py'; s=open(p).read()
old="        except Exception: time.sleep(1)"
new="        except Exception as ex:\n            STATUS[type(ex).__name__]=STATUS.get(type(ex).__name__,0)+1; time.sleep(1+attempt)"
assert old in s; s=s.replace(old,new); open(p,'w').write(s); print('exception types now logged')
PY
python3 -m py_compile duka_1m.py && echo "280 done — 270 resumes NQ from 73 complete days"
