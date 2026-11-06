#!/bin/bash
set -o pipefail
# 499_jan_feb24_rules (Finder 2026-11-06, queue item 146): jobs/499_oct24_rules.sh unchanged except the month, the memory cap (3.5 to 2.5 GB) and one added line that keeps each scored line's trades in a new local table. Wrapper as jobs/499_mar_jun24_rules.sh. Rule fixed on 5 Nov, no new cuts; Jan and Feb 2024 finished loading on 6 Nov.
# Printed labels in the source job say "Oct 2024"; read them as the month shown by the MONTH line. Pool: Jan-Feb 2024 from finder_1106e_trades, created here, with Mar-Jun from finder_1106c_trades and Jul-Oct from finder_1106_trades, read only. No DROP: cron's runner can run a second copy, so the pool reads DISTINCT. Item 145 closed on 6 Nov and is context only.
SRC=/root/pe-queue/jobs/499_oct24_rules.sh
M0="LO,HI='2024-10-01','2024-11-01'"
C0="(3_500_000_000,3_500_000_000)"
S0="    md=np.median(x.off.values); l=line(x.v.values,np.where(x.off<md,1,2))"
for s in "$M0" "$C0" "$S0"; do grep -qF "$s" "$SRC" || { echo "ERROR: line not found in source job: $s"; exit 1; }; done
python3 - <<'PY' || exit 1
import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds,psycopg2
c=psycopg2.connect(creds.pg_local()); c.autocommit=True; k=c.cursor()
k.execute("CREATE TABLE IF NOT EXISTS finder_1106e_trades(month text,nm text,e text,off float8,won boolean,p float8,v float8)")
PY
for mon in "2024-01-01 2024-02-01" "2024-02-01 2024-03-01"; do
  set -- $mon
  echo "== MONTH $1"
  export FINDER_MONTH=$1
  python3 - "$SRC" "$M0" "LO,HI='$1','$2'" "$C0" "$S0" <<'PY' | bash || exit 1
import sys
src,m0,m1,c0,s0=sys.argv[1:]
t=open(src).read().replace(m0,m1).replace(c0,'(2_500_000_000,2_500_000_000)')
add=("    if 'scored' in nm:\n"
     "        import os,psycopg2.extras as _ex; _c=psycopg2.connect(creds.pg_local()); _c.autocommit=True\n"
     "        _ex.execute_values(_c.cursor(),'INSERT INTO finder_1106e_trades VALUES %s',[(os.environ['FINDER_MONTH'],nm,str(a),float(b),bool(c_),float(d_),float(f_)) for a,b,c_,d_,f_ in zip(x.e,x.off,x.won,x.p,x.v)]); _c.close()\n")
assert t.count(s0)==1
print(t.replace(s0,add+s0))
PY
done
python3 - <<'PY'
import sys; sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds,psycopg2,numpy as np,pandas as pd
from lib_cand import line
pd.set_option('display.width',240); pd.set_option('display.max_columns',30)
c=psycopg2.connect(creds.pg_local()); k=c.cursor(); k.execute("SET work_mem='64MB'")
def get(q): k.execute(q); return pd.DataFrame(k.fetchall(),columns='month nm e off won p v'.split())
N=get("SELECT DISTINCT month,nm,e,off,won,p,v FROM finder_1106e_trades"); M=get("SELECT DISTINCT month,nm,e,off,won,p,v FROM finder_1106c_trades"); J=get("SELECT month,nm,e,off,won,p,v FROM finder_1106_trades"); c.close()
print("\n== new months by line"); print(N.groupby(['nm','month']).v.agg(['size','mean']).round(3).to_string())
def tab(R,lab):
    out=[]
    for nm,x in R.groupby('nm'):
        dup=int(x.e.duplicated().sum()); x=x.drop_duplicates('e'); md=np.median(x.off.values); l=line(x.v.values,np.where(x.off<md,1,2)); v=x.v.values
        out.append(dict(window=lab,line=nm,n=l['n'],per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],won=x.won.mean(),imp=(1/x.p).mean(),no_top=np.delete(v,v.argmax()).mean(),dup_games=dup,PASS=l['PASS']))
    return pd.DataFrame(out)
K=pd.concat([N,M,J]); K=K[K.nm.str[:3].isin(['145','146'])]
O=tab(K,'Jan-Oct 24'); print("\n== POOLED Jan-Oct 2024, items 145 (closed, context) and 146"); print(O.round(3).to_string(index=False))
S=O[O.PASS&O.line.str.startswith('146')]; print(f"\n== SURVIVORS: {len(S)}"); print(S.round(3).to_string(index=False) if len(S) else "none")
PY
